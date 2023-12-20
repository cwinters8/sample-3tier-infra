# App DB User function

Lambda function to create the app's database user when the RDS cluster is created or replaced.

## Inputs

Required function inputs

```json
{
  "admin_secret_arn": "string",
  "db_host": "string",
  "db_name": "string",
  "port": 5432, // int
  "username": "string",
  "pw_secret_arn": "string"
}
```

## Updates

If the function code is updated, you will need to regenerate the `bootstrap` binary and run `terraform apply` again.

To generate the binary, make sure you are in the `terraform/app_db_user_func` directory, then run:

```sh
GOOS=linux GOARCH=arm64 go build -tags lambda.norpc -o bootstrap main.go
```
