output "resource_group_name" {
  description = "Nome do Resource Group — referenciado via data source pelos outros 3 repositórios."
  value       = azurerm_resource_group.oficina_rg.name
}

output "aks_cluster_name" {
  description = "Nome do cluster AKS."
  value       = azurerm_kubernetes_cluster.oficina_aks.name
}

output "kube_config" {
  description = "kubeconfig para acessar o cluster (use 'az aks get-credentials' em vez deste output sempre que possível)."
  value       = azurerm_kubernetes_cluster.oficina_aks.kube_config_raw
  sensitive   = true
}
