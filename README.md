# Tech Store — Infraestructura (AWS + Terraform)

| Repositorio                                                                         | Contenido                                                         |
| ----------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| [tech-store-checkout-web](https://github.com/IamStivgo/tech-store-checkout-web)     | Frontend: SPA React                                               |
| [tech-store-checkout-api](https://github.com/IamStivgo/tech-store-checkout-api)     | Backend: API NestJS, Swagger y modelo de datos                    |
| [tech-store-checkout-infra](https://github.com/IamStivgo/tech-store-checkout-infra) | Infraestructura: Terraform y despliegue en AWS (este repositorio) |

Infraestructura serverless en AWS, definida con Terraform, para la tienda de accesorios tecnológicos: CloudFront y S3 para la SPA, API Gateway y Lambda para el API, DynamoDB, SSM Parameter Store y EventBridge Scheduler. Este repositorio crea toda la infraestructura; los repositorios web y api solo despliegan su código.

> Proyecto en construcción. Este README se completa a medida que avanza la implementación.

## Estado de la entrega

- **Desplegado:**
  - 6 tablas DynamoDB;
  - Lambdas del API y de conciliación con alias `live`;
  - HTTP API, EventBridge Scheduler;
  - SPA en S3 privado + CloudFront con security headers;
  - roles OIDC para los pipelines.
- **App:** https://d7vch0fsx8645.cloudfront.net.
- **Secretos de la pasarela:** creados en SSM (SecureString) con la CLI, fuera de Terraform.
- **Pendiente:** pasar a la Lambda del API la URL del sandbox y la llave pública (valores sensibles que no se versionan) para activar los pagos en producción.

## Estructura

```
bootstrap/          # Se aplica una vez: bucket del estado de Terraform, proveedor OIDC de GitHub y rol de Terraform
modules/
├── static-site/    # S3 + CloudFront para la SPA
├── api/            # Lambdas, API Gateway HTTP API, logs e IAM
├── database/       # Tablas DynamoDB
├── secrets/        # Parámetros SSM de la pasarela de pagos
├── scheduler/      # EventBridge Scheduler para la conciliación
└── ci-roles/       # Roles OIDC de despliegue para los repos web y api
envs/
└── prod/           # Composición de los módulos del entorno de producción
placeholder/        # Handler mínimo con el que se crean las Lambdas
```

## Requisitos

| Herramienta | Versión                                    |
| ----------- | ------------------------------------------ |
| Terraform   | ≥ 1.11                                     |
| TFLint      | Con el ruleset de AWS (`tflint --init`)    |
| Node.js     | 24 (`nvm use`), solo para los hooks de git |

## Uso local

```bash
npm ci                                            # Instala los hooks de git
tflint --init                                     # Descarga el ruleset de AWS
terraform -chdir=envs/prod init -backend=false    # Proveedores, sin conectar el estado remoto
terraform -chdir=envs/prod validate
```

Para trabajar contra el estado real (con un perfil de AWS con permisos sobre `checkout-app-*`):

```bash
terraform -chdir=envs/prod init -backend-config="bucket=checkout-app-tfstate-<account_id>"
terraform -chdir=envs/prod plan
```

| Script           | Descripción                                                                                               |
| ---------------- | --------------------------------------------------------------------------------------------------------- |
| `npm run lint`   | `terraform fmt -check` y `tflint` en todo el repositorio                                                  |
| `npm run format` | Aplica `terraform fmt` en todo el repositorio                                                             |
| `npm test`       | `terraform test` del bootstrap y de cada módulo con pruebas (proveedor simulado, sin credenciales de AWS) |

## Bootstrap (una sola vez)

`bootstrap/` crea lo que Terraform y GitHub Actions necesitan antes que todo lo demás:

- Bucket `checkout-app-tfstate-<account_id>` para el estado: versionado, cifrado, privado y solo accesible con TLS 1.2 o superior.
- Proveedor OIDC de GitHub Actions.
- Rol `checkout-app-terraform-plan`: solo lectura, para los PR de este repositorio. No puede leer los secretos de la pasarela.
- Rol `checkout-app-terraform-apply`: solo para el environment `production`. No puede modificar los recursos del bootstrap.

El backend es **parcial**: el nombre del bucket no se versiona y se pasa con `-backend-config`. El primer `apply` se hace con estado local, que luego se migra al bucket:

```bash
export AWS_PROFILE=<perfil con permisos sobre checkout-app-*>
mv bootstrap/backend.tf bootstrap/backend.tf.off     # 1. Primer apply con estado local
terraform -chdir=bootstrap init
terraform -chdir=bootstrap apply
STATE_BUCKET=$(terraform -chdir=bootstrap output -raw state_bucket_name)
mv bootstrap/backend.tf.off bootstrap/backend.tf     # 2. Migra el estado al bucket creado
terraform -chdir=bootstrap init -migrate-state -backend-config="bucket=$STATE_BUCKET"
rm bootstrap/terraform.tfstate bootstrap/terraform.tfstate.backup
```

Después, en cualquier máquina:

```bash
terraform -chdir=bootstrap init -backend-config="bucket=checkout-app-tfstate-<account_id>"
```

## Secretos de la pasarela de pagos

La llave privada, el secreto de integridad y el secreto de eventos del sandbox se guardan como parámetros `SecureString` en SSM y **no los gestiona Terraform**. Si los gestionara, al refrescar leería el valor descifrado: el secreto quedaría en el estado y el rol de `plan` de los PR, que tiene denegada su lectura, fallaría. El módulo `secrets` solo expone sus nombres (`terraform output payment_parameter_names`) y sus ARN para las políticas de las Lambdas.

Se crean o rotan una vez con la CLI, sin que el valor quede en el historial de la terminal:

```bash
for secret in private-key integrity-secret events-secret; do
  read -rsp "Valor de ${secret}: " value && echo
  aws ssm put-parameter --name "/checkout-app/prod/payment/${secret}" \
    --type SecureString --value "$value" --overwrite >/dev/null
done
unset value
```

## Flujo de trabajo

- Ramas: `main` (estable), `develop` (integración) y `feature/HU-xxx-descripcion`.
- Commits en inglés con [Conventional Commits](https://www.conventionalcommits.org/) más el tipo `infra`, validados por commitlint.
- Antes de cada commit, lint-staged ejecuta `terraform fmt` y `tflint` sobre los archivos `.tf` modificados.
- Integración continua con GitHub Actions en cada PR y push a `develop` y `main`: `terraform fmt -check`, `tflint`, `terraform validate` de `bootstrap` y `envs/prod` y las pruebas del bootstrap y de los módulos. Dependabot propone actualizaciones semanales del proveedor de AWS y de las acciones.

## Despliegue (GitHub Actions con OIDC, sin llaves de AWS)

| Workflow                       | Cuándo                                                  | Rol                                          | Qué hace                                                                                                                                                                 |
| ------------------------------ | ------------------------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ci.yml`, job `Terraform plan` | Cada PR del propio repositorio (no forks ni Dependabot) | `checkout-app-terraform-plan` (solo lectura) | `terraform plan` de `envs/prod` contra el estado real y comentario en el PR con el resumen y el plan completo                                                            |
| `apply.yml`                    | Merge a `main` (o manual)                               | `checkout-app-terraform-apply`               | Tras la aprobación del environment `production`: `plan` + `apply` de `envs/prod`, verificación de los parámetros `/checkout-app/prod/deploy/*` y resumen con los outputs |

El repositorio es público: el ID de la cuenta se enmascara en los logs y se reemplaza por `<account-id>` en los comentarios y resúmenes. Configuración del repositorio: variable `AWS_REGION` y **secrets** `TF_STATE_BUCKET`, `AWS_TERRAFORM_PLAN_ROLE_ARN` y `AWS_TERRAFORM_APPLY_ROLE_ARN` (salidas del bootstrap). Son secrets porque contienen el ID de la cuenta: GitHub imprime los parámetros de las acciones antes de que se active el enmascarado, y solo los secrets quedan ocultos desde el inicio.
