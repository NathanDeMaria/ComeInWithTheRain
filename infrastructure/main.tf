provider "aws" {
  profile = "default"
  region  = "us-east-2"
  version = "~> 2.69"
}

resource "aws_iam_role" "come_in_with_the_rain" {
  name = "come_in_with_the_rain"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

data "aws_iam_policy" "AWSLambdaBasicExecutionRole" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy_attachment" "policy_attachment" {
  name       = "attachment"
  roles      = [aws_iam_role.come_in_with_the_rain.name]
  policy_arn = data.aws_iam_policy.AWSLambdaBasicExecutionRole.arn
}

resource "aws_lambda_function" "come_in_with_the_rain" {
  filename      = "../lambda_function_payload.zip"
  function_name = "come_in_with_the_rain"
  role          = aws_iam_role.come_in_with_the_rain.arn
  handler       = "rain.post_result"

  source_code_hash = filebase64sha256("../lambda_function_payload.zip")
  timeout          = 60
  memory_size      = 256

  runtime = "provided"
  # Created via https://github.com/NathanDeMaria/aws-lambda-r-runtime/tree/ceddfe8385fb5c3010f34cff7651ba94fdab7a74#aws-lambda-r-runtime-fork
  layers = [
    "arn:aws:lambda:us-east-2:080353813015:layer:r-runtime-3_6_0:1",
    "arn:aws:lambda:us-east-2:080353813015:layer:r-tidyverse-3_6_0:1"
  ]

  environment {
    variables = {
      USER_AGENT     = var.USER_AGENT
      LATITUDE       = var.LATITUDE
      LONGITUDE      = var.LONGITUDE
      PUSH_API_KEY   = var.PUSH_API_KEY
      PUSH_DEVICE_ID = var.PUSH_DEVICE_ID
    }
  }
}

module "schedule" {
  source      = "./schedule"
  lambda_arn  = aws_lambda_function.come_in_with_the_rain.arn
  lambda_name = aws_lambda_function.come_in_with_the_rain.function_name
}
