# k3s-n8n

Repositorio de configuración para desplegar **n8n** (automation workflow tool) en un cluster **k3s** con acceso público, SSL/TLS y base de datos PostgreSQL persistente.

## 📋 Requisitos

- Cluster k3s (v1.28+) - ✅ **Detectado: v1.34.6+k3s1**
- kubectl configurado
- Helm 3.x
- **cert-manager** - ✅ **Ya instalado (letsencrypt-prod, letsencrypt-staging configurados)**
- **external-dns** - ✅ **Ya instalado**
- Acceso DNS configurado para los dominios:
  - `n8n-dev.qforexwin.com` (dev)
  - `n8n-pre.qforexwin.com` (pre)
  - `n8n.qforexwin.com` (pro)

## 📁 Estructura del Repositorio

```
k3s-n8n/
├── helm/
│   └── n8n/                    # Chart de Helm principal
│       ├── templates/          # Templates de Kubernetes
│       ├── values.yaml         # Valores base
│       ├── values-dev.yaml     # Valores desarrollo
│       ├── values-pre.yaml     # Valores preproducción
│       └── values-pro.yaml     # Valores producción
├── manifests/
│   └── cert-manager/           # Configuración de cert-manager
├── scripts/                    # Scripts de automatización
│   ├── install-cert-manager.sh # Instalar cert-manager
│   ├── deploy.sh               # Desplegar n8n
│   ├── backup.sh               # Backup de datos
│   └── uninstall.sh            # Desinstalar n8n
└── README.md                   # Este archivo
```

## 🚀 Instalación Rápida

### 1. Preparar el entorno

Asegúrate de que los dominios apuntan a tu cluster k3s:

```bash
# Verificar DNS (usando external-dns ya instalado)
dig n8n.qforexwin.com
```

### 2. Verificar cert-manager y external-dns (ya instalados)

```bash
# Verificar que cert-manager está corriendo
kubectl get pods -n cert-manager
kubectl get clusterissuer

# Verificar external-dns
kubectl get pods -n external-dns
```

> **Nota**: Tu cluster ya tiene cert-manager y external-dns instalados. No es necesario volver a instalarlos.

### 3. Configurar credenciales

**IMPORTANTE:** Antes de desplegar, edita los archivos `values-*.yaml` y cambia:

- `n8n.basicAuth.password` - Contraseña de acceso a n8n
- `n8n.encryptionKey` - Clave de encriptación (32 caracteres)
- `postgresql.auth.password` - Contraseña de PostgreSQL
- `ingress.certManager.email` - Email para Let's Encrypt

### 4. Desplegar n8n

```bash
# Desarrollo
./scripts/deploy.sh dev

# Preproducción
./scripts/deploy.sh pre

# Producción
./scripts/deploy.sh pro
```

### 5. Verificar despliegue

```bash
# Ver pods
kubectl get pods -n n8n-pro

# Ver servicios
kubectl get svc -n n8n-pro

# Ver ingress
kubectl get ingress -n n8n-pro

# Ver certificado SSL
kubectl get certificate -n n8n-pro
```

## 🔧 Configuración

### Cambiar el email de Let's Encrypt

Edita los archivos en `manifests/cert-manager/` y actualiza el campo `email`:

```yaml
email: tu-email@qforexwin.com
```

Luego aplica los cambios:

```bash
kubectl apply -f manifests/cert-manager/
```

### Actualizar contraseñas

Para cambiar contraseñas después del despliegue:

```bash
# Actualizar secreto de n8n
kubectl create secret generic n8n-pro-auth \
  --from-literal=username=admin \
  --from-literal=password=NUEVA_PASSWORD \
  --from-literal=encryptionKey=NUEVA_ENCRYPTION_KEY_32CHARS \
  -n n8n-pro --dry-run=client -o yaml | kubectl apply -f -

# Reiniciar pods
kubectl rollout restart deployment/n8n-pro -n n8n-pro
```

## 💾 Backup y Recuperación

### Crear backup

```bash
# Backup completo del entorno pro
./scripts/backup.sh pro
```

Los backups se guardan en `backups/pro/YYYYMMDD_HHMMSS/`.

### Restaurar backup

```bash
# Restaurar base de datos
kubectl exec -i n8n-pro-postgresql-0 -n n8n-pro -- psql -U n8n_pro < backup.sql

# Restaurar datos de n8n
kubectl cp n8n_data.tar.gz n8n-pro-xxx:/tmp/ -n n8n-pro
kubectl exec n8n-pro-xxx -n n8n-pro -- tar xzf /tmp/n8n_data.tar.gz -C /
```

## 🔄 Gestión del ciclo de vida

### Actualizar n8n

```bash
# Editar values-pro.yaml y cambiar la versión de la imagen
# image:
#   tag: "1.51.0"  # Nueva versión

# Redesplegar
./scripts/deploy.sh pro
```

### Escalar réplicas

```bash
# Escalar a 3 réplicas en producción
kubectl scale deployment n8n-pro --replicas=3 -n n8n-pro
```

### Ver logs

```bash
# Logs de n8n
kubectl logs -f -n n8n-pro -l app.kubernetes.io/name=n8n

# Logs de PostgreSQL
kubectl logs -f -n n8n-pro -l app.kubernetes.io/name=postgresql
```

## 🗑️ Desinstalación

```bash
# Desarrollo
./scripts/uninstall.sh dev

# Preproducción
./scripts/uninstall.sh pre

# Producción (requiere confirmación explícita)
./scripts/uninstall.sh pro
```

## 🔒 Seguridad

### Características de seguridad incluidas

- ✅ Autenticación básica habilitada por defecto
- ✅ Conexiones SSL/TLS con certificados Let's Encrypt
- ✅ Encriptación de datos sensibles de n8n
- ✅ Contraseñas en Kubernetes Secrets
- ✅ Network policies (recomendado añadir manualmente)

### Buenas prácticas adicionales

1. **Cambia todas las contraseñas por defecto** antes de desplegar en producción
2. **Habilita 2FA** en n8n una vez accedas por primera vez
3. **Configura un firewall** para restringir accesos administrativos
4. **Habilita audit logging** en n8n para entornos de producción
5. **Realiza backups periódicos** automatizados

## 🐛 Solución de Problemas

### El certificado SSL no se emite

```bash
# Verificar estado del certificado
kubectl describe certificate n8n-pro -n n8n-pro

# Ver logs de cert-manager
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager

# Verificar que el dominio resuelve correctamente
kubectl run -it --rm debug --image=curlimages/curl -- curl -v http://n8n.qforexwin.com/
```

### n8n no puede conectar a PostgreSQL

```bash
# Verificar estado de PostgreSQL
kubectl get pods -n n8n-pro -l app.kubernetes.io/name=postgresql

# Ver logs de PostgreSQL
kubectl logs -n n8n-pro -l app.kubernetes.io/name=postgresql

# Verificar variables de entorno
kubectl exec -it n8n-pro-xxx -n n8n-pro -- env | grep DB_
```

### Problemas de almacenamiento

```bash
# Verificar PVCs
kubectl get pvc -n n8n-pro

# Verificar PVs
kubectl get pv

# Verificar StorageClass
kubectl get storageclass
```

## 📚 Recursos

- [Documentación de n8n](https://docs.n8n.io/)
- [Helm Charts de Bitnami](https://charts.bitnami.com/)
- [cert-manager](https://cert-manager.io/)
- [k3s Documentation](https://docs.k3s.io/)

## 📞 Soporte

Para problemas o consultas relacionadas con este despliegue, contacta al equipo técnico.

---

**Nota:** Este proyecto está diseñado para funcionar con k3s pero puede adaptarse a otros clusters Kubernetes compatibles.
