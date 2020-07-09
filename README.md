An R script that uses NOAA data to tell me when I need to water my lawn (via [Pushbullet](https://www.pushbullet.com/)).

Uses [this fork](https://github.com/NathanDeMaria/aws-lambda-r-runtime?organization=NathanDeMaria&organization=NathanDeMaria#aws-lambda-r-runtime-fork) to run R in AWS Lambda.

## Running

`make push` will:

- Zip up the `rain.R` function.
- Use `terraform` to deploy it as an AWS Lambda function
- Schedule the Lambda function with a CloudWatch Event Rule

## Config

Copy `infrastructure/secrets.tfvars.template` to `infrastructure/secrets.tfvars`, fill out the values.
