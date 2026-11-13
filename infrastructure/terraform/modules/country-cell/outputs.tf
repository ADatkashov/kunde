output "cell" {
  description = "Normalised, secret-free cell specification for provider adapters and Helm values."
  value       = terraform_data.contract.output
}
