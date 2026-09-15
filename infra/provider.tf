terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Este repositório é o "dono" do Resource Group — os outros 3 repositórios
# (oficina-infra-banco-dados, oficina-lambda-auth-cpf, oficina-app) só leem
# esse Resource Group via `data source`, nunca o criam.
resource "azurerm_resource_group" "oficina_rg" {
  name     = "oficina-resources"
  location = "Brazil South"
}
