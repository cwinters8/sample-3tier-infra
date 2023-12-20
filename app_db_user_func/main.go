package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/secretsmanager"
	"github.com/jackc/pgx/v5"
)

type dbUser struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type ErrNoRows struct{}

func (e ErrNoRows) Error() string {
	return "no rows in result set"
}

func (e ErrNoRows) Is(err error) bool {
	return strings.Contains(err.Error(), e.Error())
}

func (u *dbUser) new(ctx context.Context, db *pgx.Conn) error {
	row := db.QueryRow(ctx, "SELECT usename FROM pg_catalog.pg_user WHERE usename=$1", u.Username)
	var existingUser string
	noRows := ErrNoRows{}
	if err := row.Scan(&existingUser); err != nil && !noRows.Is(err) {
		return fmt.Errorf("failed to check for existing user: %w", err)
	}
	fmt.Println("checked for existing db user")
	sqlVerb := "CREATE"
	// if user exists, update the password
	if len(existingUser) > 0 {
		fmt.Printf("Database user `%s` already exists. Updating password...\n", u.Username)
		sqlVerb = "ALTER"
	}
	if _, err := db.Exec(
		ctx,
		fmt.Sprintf("%s USER \"%s\" WITH PASSWORD '%s'", sqlVerb, u.Username, u.Password),
	); err != nil {
		return fmt.Errorf("failed to %s db user: %w", strings.ToLower(sqlVerb), err)
	}
	fmt.Println("created or updated db user")
	return nil
}

type Event struct {
	AdminSecretARN    string `json:"admin_secret_arn"`
	DatabaseHost      string `json:"db_host"`
	DatabaseName      string `json:"db_name"`
	Port              int    `json:"port"`
	Username          string `json:"username"`
	PasswordSecretARN string `json:"pw_secret_arn"`
}

func Handler(ctx context.Context, event *Event) error {
	if event == nil {
		return fmt.Errorf("received nil event")
	}
	fmt.Printf("received event: %+v\n", *event)
	if err := checkHostPort(event.DatabaseHost, event.Port); err != nil {
		return fmt.Errorf("failed to connect to db host: %w", err)
	}
	smEndpoint := os.Getenv("AWS_ENDPOINT_URL_SECRETS_MANAGER")
	if len(smEndpoint) == 0 {
		return fmt.Errorf("secrets manager endpoint not set")
	}
	fmt.Printf("got secrets manager endpoint `%s`\n", smEndpoint)
	tryPorts := []int{80, 443}
	var succeededPorts []int
	var errs []error
	for _, port := range tryPorts {
		if err := checkHostPort(smEndpoint, port); err == nil {
			succeededPorts = append(succeededPorts, port)
		} else {
			errs = append(errs, err)
		}
	}
	if len(succeededPorts) == 0 {
		return fmt.Errorf("failed to connect to secrets manager endpoint `%s`\ngot errors: %v", smEndpoint, errs)
	}
	fmt.Printf("connected to secrets manager endpoint `%s` on ports %v", smEndpoint, succeededPorts)
	sess, err := session.NewSession()
	if err != nil {
		return fmt.Errorf("failed to generate new AWS session: %w", err)
	}
	sm := secretsmanager.New(sess)
	rawAdmin, err := sm.GetSecretValue(&secretsmanager.GetSecretValueInput{
		SecretId: &event.AdminSecretARN,
	})
	if err != nil {
		return fmt.Errorf("failed to get admin password secret: %w", err)
	}
	fmt.Println("got admin db user secret")
	var admin dbUser
	if err := json.Unmarshal([]byte(*rawAdmin.SecretString), &admin); err != nil {
		return fmt.Errorf("failed to unmarshal admin user json: %w", err)
	}
	fmt.Println("unmarshalled db user secret json")
	pw, err := sm.GetSecretValue(&secretsmanager.GetSecretValueInput{
		SecretId: &event.PasswordSecretARN,
	})
	if err != nil {
		return fmt.Errorf("failed to get password secret: %w", err)
	}
	fmt.Println("got app db user secret")
	dbURL := fmt.Sprintf(
		"postgres://%s@%s:%d/%s",
		admin.Username,
		event.DatabaseHost,
		event.Port,
		event.DatabaseName,
	)
	cfg, err := pgx.ParseConfig(dbURL)
	if err != nil {
		return fmt.Errorf("failed to parse pg config: %w", err)
	}
	cfg.Password = admin.Password
	fmt.Println("got db connection config")
	db, err := pgx.ConnectConfig(ctx, cfg)
	if err != nil {
		return fmt.Errorf("failed to connect to database: %w", err)
	}
	fmt.Println("connected to db")
	user := dbUser{
		Username: event.Username,
		Password: *pw.SecretString,
	}
	return user.new(ctx, db)
}

func main() {
	lambda.Start(Handler)
}

func checkHostPort(host string, port int) error {
	timeout := 3 * time.Second
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, fmt.Sprintf("%d", port)), timeout)
	if err != nil {
		return fmt.Errorf("connection failure to %s on port %d: %w", host, port, err)
	}
	if conn != nil {
		defer conn.Close()
		fmt.Printf("opened connection to %s on port %d\n", host, port)
	}
	return nil
}
