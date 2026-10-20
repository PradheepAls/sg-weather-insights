locals {
  name        = "sgw-${var.environment}"
  is_lifetime = var.environment == "lifetime"
  has_farm    = var.frontend_count > 0

  # Three databases per OutSystems 11 environment, and least-privilege logins for them.
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

  # Platform consoles and test tooling that must not be public.
  admin_paths = ["/ServiceCenter*", "/LifeTime*", "/BDDFramework*", "/CI_CDProbe*", "/ServiceManager*"]
}
