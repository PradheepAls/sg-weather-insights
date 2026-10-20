locals {
  name        = "${var.project}-${var.environment}"
  is_lifetime = var.environment == "lifetime"

  tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
  })

  # Database catalogs and logins; every OutSystems 11 environment needs platform, log and session.
  catalogs = {
    platform = "${var.environment}_outsystems"
    log      = "${var.environment}_outsystems_log"
    session  = "${var.environment}_outsystems_session"
  }
  logins = {
    admin       = "${var.environment}_os_admin"
    runtime     = "${var.environment}_os_runtime"
    log_admin   = "${var.environment}_os_log_admin"
    log_runtime = "${var.environment}_os_log_runtime"
    session     = "${var.environment}_os_session"
  }

  controller_fqdn = "controller.${var.environment}.${var.private_zone_name}"

  # LifeTime is a single server; application environments may add a front-end farm.
  frontend_enabled = !local.is_lifetime && var.frontend_max > 0

  # Paths that must never be reachable from the public internet.
  admin_paths = ["/ServiceCenter*", "/LifeTime*", "/CI_CDProbe*", "/BDDFramework*", "/ServiceManager*"]

  # Inter-server OutSystems service ports (deployment controller/service, scheduler, SMS, logging)
  # and RabbitMQ for the Cache Invalidation Service.
  platform_ports = [
    { from = 12000, to = 12004, desc = "OutSystems platform services" },
    { from = 5672, to = 5672, desc = "Cache Invalidation Service (RabbitMQ)" },
  ]
}
