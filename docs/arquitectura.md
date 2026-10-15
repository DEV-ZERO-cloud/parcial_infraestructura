# Arquitectura de Infraestructura — Taller 8 (Promoción de Imagen por Digest)

## 1. Resumen de la arquitectura en AWS

La solución implementa la promoción inmutable de un único artefacto contenedorizado entre los ambientes de **pruebas** (`pruebas`) y **producción** (`produccion`) sobre **AWS** gestionado íntegramente con **Terraform** (`infraestructura/`):

1. **Registro único de contenedores (`Amazon ECR`)**:
   - Repositorio `estrella-app` con **tags inmutables (`IMMUTABLE`)**, escaneo automático al subir (`scan_on_push = true`), cifrado KMS y política de ciclo de vida (máximo 20 imágenes para control de costos).
   - La imagen Docker se construye **una sola vez** por commit en GitHub Actions, se etiqueta con el SHA del commit (`<ecr_url>:<git_sha>`), se analiza con **Trivy** y se obtiene su digest inmutable (`sha256:...`).

2. **Ambientes aislados y parametrizados (`for_each` sobre `pruebas` y `produccion`)**:
   - **Application Load Balancer (ALB)** público en puerto TCP `80` por ambiente (`estrella-pruebas` y `estrella-produccion`).
   - **Amazon ECS con AWS Fargate** (`0.25 vCPU` / `256` unidades de CPU y `512 MB` de RAM, `desired_count = 1` por ambiente para mínimo costo).
   - **Grupos de seguridad (Security Groups)** de mínimo privilegio: el ALB recibe tráfico HTTP (`80`) desde Internet y solo permite salida al puerto `8080` del grupo de seguridad de la tarea ECS; la tarea ECS solo acepta tráfico desde el ALB en el puerto `8080` y salida HTTPS (`443`) para descargar la imagen de ECR y enviar logs a CloudWatch.
   - **CloudWatch Logs** (`/ecs/estrella-pruebas` y `/ecs/estrella-produccion`) con retención de 30 días.

3. **Autenticación y promoción sin reconstrucción**:
   - **IAM OIDC (`estrella-github-actions`)**: permite a GitHub Actions asumir un rol temporal mediante `sts:AssumeRoleWithWebIdentity` sin almacenar claves estáticas en el repositorio.
   - Tanto el despliegue en `pruebas` como la promoción a `produccion` (tras la aprobación manual en GitHub Environments) actualizan la definición de tarea de ECS inyectando **exactamente la misma referencia por digest**: `<ecr_repository_url>@sha256:<digest>`.

## 2. Diagrama de arquitectura

```mermaid
flowchart TB
    subgraph GH["GitHub Actions (CI/CD)"]
        Commit["Commit en main (SHA)"] --> Build["1. Docker Build único\nTag: <sha>"]
        Build --> Trivy["2. Escaneo Trivy\n(bloquea si falla)"]
        Trivy --> Push["3. Push a Amazon ECR\nObtiene @sha256:<digest>"]
        Push --> DeployTest["4. Despliegue en Pruebas\nUsa imagen@sha256:<digest>"]
        DeployTest --> HttpTest["5. Prueba HTTP automática\nGET /health"]
        HttpTest --> Approval["6. GitHub Environment: production\n(Aprobación Manual Requerida)"]
        Approval --> PromoteProd["7. Promoción a Producción\nSin rebuild: mismo @sha256:<digest>"]
    end

    subgraph AWS["AWS Cloud (us-east-1) — Gestionado con Terraform"]
        OIDC["IAM Role OIDC\nestrella-github-actions"]
        ECR[("Amazon ECR\nestrella-app\n(IMMUTABLE + KMS)")]

        subgraph EnvTest["Ambiente: pruebas"]
            ALB_T["ALB Público :80\nestrella-pruebas"] --> TG_T["Target Group :8080"]
            TG_T --> ECS_T["ECS Fargate Service\nCluster: estrella-pruebas\nImagen: @sha256:<digest>"]
            ECS_T --> CW_T["CloudWatch Logs\n/ecs/estrella-pruebas"]
        end

        subgraph EnvProd["Ambiente: produccion"]
            ALB_P["ALB Público :80\nestrella-produccion"] --> TG_P["Target Group :8080"]
            TG_P --> ECS_P["ECS Fargate Service\nCluster: estrella-produccion\nImagen: @sha256:<digest>"]
            ECS_P --> CW_P["CloudWatch Logs\n/ecs/estrella-produccion"]
        end
    end

    GH -. "Asume rol vía OIDC" .-> OIDC
    Push ==> ECR
    DeployTest ==> ECS_T
    PromoteProd ==> ECS_P
    ECS_T -. "Pull por digest" .-> ECR
    ECS_P -. "Pull por digest" .-> ECR
    HttpTest -. "Verifica 200 OK y commit" .-> ALB_T