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

Para que `/health` informe el commit en la imagen publicada, el paso `build-push-action`
de `.github/workflows/deploy.yml` debe pasar:

```yaml
build-args: |
  GIT_COMMIT=${{ github.sha }}
```

### Recuperar el digest de la imagen publicada

```bash
docker buildx imagetools inspect ghcr.io/<owner>/<repo>:<commit sha>   # muestra "Digest: sha256:..."
```

El workflow también lo imprime y lo expone como salida `digest` del job `build-and-scan`.
