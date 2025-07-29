#!/bin/bash

# Inicializar Terraform
cd environments/prod
terraform init

# Planejar mudanças
terraform plan -out=tfplan

# Aplicar mudanças
terraform apply tfplan

# Para mudanças sem downtime
terraform apply -target=module.aurora.aws_rds_cluster_instance.aurora["ecommerce-prod-reader-3"]