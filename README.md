# parcial_infraestructura

## Aplicación: rastreador de lectura

Servidor HTTP en Python (solo biblioteca estándar, sin dependencias) que sirve una
interfaz para marcar cada libro de la serie principal como pendiente, leyendo o leído.
El progreso se guarda en el navegador (localStorage); el contenedor no guarda estado
ni usa credenciales.

| Ruta | Respuesta |
|---|---|
| `/` | Interfaz web |
| `/health` | `{"status":"ok","app":"horus-tracker","version":"1.0.0","commit":"<sha>"}` |

El campo `commit` sale de la variable `GIT_COMMIT`, fijada al construir la imagen.
La interfaz también muestra el commit abreviado al pie de la página.

### Ejecutar sin Docker

```bash
GIT_COMMIT=$(git rev-parse HEAD) python3 app/app.py
curl http://localhost:8080/health
```

### Construir y ejecutar con Docker

```bash
docker build --build-arg GIT_COMMIT=$(git rev-parse HEAD) -t horus-tracker:$(git rev-parse HEAD) .
docker run --rm -p 8080:8080 horus-tracker:$(git rev-parse HEAD)
curl http://localhost:8080/health
```

Abre http://localhost:8080 para usar la interfaz.

### Imagen

- Base `python:3.12-slim`, usuario no root (UID 10001), sin shell de login.
- Sin secretos: `.dockerignore` excluye `.env`, llaves, `.git` y estado de Terraform.
- `HEALTHCHECK` contra `/health`.
- Nombre y etiqueta publicados por CI: `ghcr.io/<owner>/<repo>:<commit sha>`.

El workflow de CI ya pasa `GIT_COMMIT=${{ github.sha }}` al `build-push-action`,
así que la imagen publicada reporta el commit que la produjo.

### Recuperar el digest de la imagen publicada

```bash
docker buildx imagetools inspect ghcr.io/<owner>/<repo>:<commit sha>   # muestra "Digest: sha256:..."
```

El workflow también lo imprime y lo expone como salida `digest` del job `build-and-scan`.

## Pipeline CI/CD

El workflow [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)
promueve la misma imagen entre ambientes, identificado por su digest:

```
push a main → build único (tag = SHA del commit)
           → Trivy sobre la imagen por digest (umbral HIGH/CRITICAL)
           → publicación en GHCR
           → deploy-testing (misma referencia por digest) → prueba HTTP /health
           → deploy-production (espera aprobación del Environment) → prueba HTTP
           → resumen-promocion (compara digest publicado vs. confirmado en cada ambiente)
```

| Job | Qué hace |
|---|---|
| `build-and-scan` | Construye **una sola vez**, publica con tag del SHA, analiza con Trivy y expone el digest |
| `deploy-testing` | Envía la referencia inmutable al adaptador y ejecuta la prueba HTTP |
| `deploy-production` | Requiere aprobación del Environment `production`; promueve la misma referencia sin reconstruir |
| `resumen-promocion` | Imprime y compara el digest publicado con el confirmado en cada ambiente; falla si difieren |

Los jobs de despliegue solo se ejecutan cuando la variable de repositorio
`DEPLOY_ADAPTER_READY` vale `true`; mientras no exista la infraestructura,
el run valida build → Trivy → publicación y omite los despliegues.

La configuración de Environments, secretos y aprobación está en
[`docs/configuracion_github.md`](docs/configuracion_github.md) y el detalle
de pruebas en [`docs/pruebas_workflows.md`](docs/pruebas_workflows.md).

Para validar el mismo flujo en local (build con commit, `/health` y Trivy):

```bash
bash scripts/validar_pipeline_local.sh
```
