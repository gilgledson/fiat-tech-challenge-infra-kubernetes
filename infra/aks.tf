resource "azurerm_kubernetes_cluster" "oficina_aks" {
  name                = "oficina-aks-cluster"
  location            = azurerm_resource_group.oficina_rg.location
  resource_group_name = azurerm_resource_group.oficina_rg.name
  dns_prefix          = "oficina-aks"

  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = var.node_vm_size
  }

  identity {
    type = "SystemAssigned"
  }

  oidc_issuer_enabled = true
}
