push:
	zip lambda_function_payload.zip rain.R
	cd infrastructure/ && terraform init && terraform apply -var-file="secrets.tfvars"
