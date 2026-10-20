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
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "server" {
  name = "outsystems-bootstrap"
  role = aws_iam_role.server.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadPlatformSecrets"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = compact([
          aws_secretsmanager_secret.platform.arn,
          aws_secretsmanager_secret.private_key.arn,
          try(aws_db_instance.this.master_user_secret[0].secret_arn, ""),
        ])
      },
      {
        # Only the controller writes the key, but instance roles are shared; the bootstrap script
        # writes once (when no version exists) and front-ends only read.
        Sid      = "PublishPrivateKey"
        Effect   = "Allow"
        Action   = ["secretsmanager:PutSecretValue"]
        Resource = [aws_secretsmanager_secret.private_key.arn]
      },
      {
        Sid    = "ReadArtifacts"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          "arn:aws:s3:::${var.artifacts_bucket}/bootstrap/${var.environment}/*",
          "arn:aws:s3:::${var.artifacts_bucket}/${var.license_s3_key}",
          "arn:aws:s3:::${var.artifacts_bucket}/installers/*",
        ]
      },
      {
        Sid      = "DecryptWithProjectKey"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:Encrypt"]
        Resource = [var.kms_key_arn]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "server" {
  name = "${local.name}-server"
  role = aws_iam_role.server.name
  tags = local.tags
}
