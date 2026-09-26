# Tech Store — Infraestructura (AWS + Terraform)

| Repositorio | Contenido |
|---|---|
| [tech-store-checkout-web](https://github.com/IamStivgo/tech-store-checkout-web) | Frontend: SPA React |
| [tech-store-checkout-api](https://github.com/IamStivgo/tech-store-checkout-api) | Backend: API NestJS, Swagger y modelo de datos |
| [tech-store-checkout-infra](https://github.com/IamStivgo/tech-store-checkout-infra) | Infraestructura: Terraform y despliegue en AWS (este repositorio) |

Infraestructura serverless en AWS, definida con Terraform, para la tienda de accesorios tecnológicos: CloudFront y S3 para la SPA, API Gateway y Lambda para el API, DynamoDB, SSM Parameter Store y EventBridge Scheduler. Este repositorio crea toda la infraestructura; los repositorios web y api solo despliegan su código.

> Proyecto en construcción. Este README se completa a medida que avanza la implementación.

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

| Herramienta | Versión |
|---|---|
| Terraform | ≥ 1.11 |
| TFLint | Con el ruleset de AWS (`tflint --init`) |
| Node.js | 24 (`nvm use`), solo para los hooks de git |

## Uso local

```bash
npm ci                                            # Instala los hooks de git
tflint --init                                     # Descarga el ruleset de AWS
terraform -chdir=envs/prod init -backend=false    # Proveedores, sin conectar el estado remoto
terraform -chdir=envs/prod validate
```

| Script | Descripción |
|---|---|
| `npm run lint` | `terraform fmt -check` y `tflint` en todo el repositorio |
| `npm run format` | Aplica `terraform fmt` en todo el repositorio |
| `npm test` | `terraform test` de cada módulo con pruebas (proveedor simulado, sin credenciales de AWS) |

## Flujo de trabajo

- Ramas: `main` (estable), `develop` (integración) y `feature/HU-xxx-descripcion`.
- Commits en inglés con [Conventional Commits](https://www.conventionalcommits.org/) más el tipo `infra`, validados por commitlint.
- Antes de cada commit, lint-staged ejecuta `terraform fmt` y `tflint` sobre los archivos `.tf` modificados.
- Integración continua con GitHub Actions en cada PR y push a `develop` y `main`: `terraform fmt -check`, `tflint`, `terraform validate` de `bootstrap` y `envs/prod` y las pruebas de los módulos. Dependabot propone actualizaciones semanales del proveedor de AWS y de las acciones.
