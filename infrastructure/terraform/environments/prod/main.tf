terraform {
  required_version = ">= 1.9.0"
  # No backend and no provider: production hosting/residency is not decided
  # (TASK-051 / D-08). This root only validates the cell contract.
}

module "cell" {
  source = "../../modules/country-cell"

  country             = "kz"
  environment         = "prod"
  data_region_country = "kz"
  provider_id         = "unselected"
}

output "cell" {
  value = module.cell.cell
}
