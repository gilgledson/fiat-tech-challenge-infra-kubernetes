variable "node_count" {
  description = "Quantidade de nós do cluster. Com um nó de 2 vCPUs, os três microsserviços, o RabbitMQ, o MongoDB, o Traefik e o New Relic cabem, mas sem folga para o HPA escalar; com dois nós há folga."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 5
    error_message = "node_count deve ficar entre 1 e 5."
  }
}

variable "node_vm_size" {
  description = "Tamanho da VM dos nós do cluster."
  type        = string
  default     = "Standard_D2s_v3"
}
