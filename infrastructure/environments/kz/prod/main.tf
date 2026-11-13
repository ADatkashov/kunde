terraform {
  required_version = ">= 1.9.0"
  # Remote state backend is intentionally not configured: it needs the
  # provider and bucket chosen at the procurement gate (TASK-051). Never
  # apply this root with local state outside a throwaway sandbox.
}

module "cell" {
  source = "../../../modules/country-cell"

  country             = "kz"
  environment         = "prod"
  data_region_country = "kz"
  provider_id         = "unselected"
  region              = ""
}

output "cell" {
  value = module.cell.cell
}
