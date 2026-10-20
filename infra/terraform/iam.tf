resource "aws_iam_role" "server" {
  name = "${local.name}-server"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# SSM Session Manager replaces RDP and bastion hosts.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "bootstrap" {
  name = "outsystems-bootstrap"
  role = aws_iam_role.server.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSecrets"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = compact([
          aws_secretsmanager_secret.platform.arn,
          aws_secretsmanager_secret.private_key.arn,
          try(aws_db_instance.this.master_user_secret[0].secret_arn, ""),
        ])
      },
      {
        Sid      = "ControllerPublishesPrivateKey"
        Effect   = "Allow"
        Action   = ["secretsmanager:PutSecretValue"]
        Resource = [aws_secretsmanager_secret.private_key.arn]
      },
      {
        Sid      = "ReadLicence"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::${var.license_bucket}/${var.license_key}"]
      },
      {
        Sid      = "UseProjectKey"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
        Resource = [aws_kms_key.this.arn]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "server" {
  name = "${local.name}-server"
  role = aws_iam_role.server.name
}
