# 🏥 Bioko Health — Annobón

**Isla de Annobón — República de Guinea Ecuatorial**

> ⚠️ **Estado: Pendiente de aprobación del Ministerio de Sanidad**
>
> El sistema está técnicamente listo. La operación está condicionada a la
> decisión del Ministerio sobre la modalidad de conectividad y el
> presupuesto adicional correspondiente.

## Opciones de conectividad

Configurar `ANNOBON_SYNC_MODE` en `.env` según lo que decida el Ministerio:

| Opción | Configuración | Coste adicional | Notas |
|--------|--------------|-----------------|-------|
| Internet semanal | `ANNOBON_SYNC_MODE=weekly` | Bajo (~1.2M XAF/año) | Requiere cobertura 4G |
| Sync manual | `ANNOBON_SYNC_MODE=manual` | Mínimo | Operador activa manualmente |
| Satélite | `ANNOBON_SYNC_MODE=satellite` | Alto (~18M XAF/año) | Conectividad garantizada |

## Funcionamiento sin conectividad

Mientras no haya conexión con el Ministerio, Annobón opera de forma
completamente independiente. Las instalaciones de la isla se conectan
al nodo provincial de Annobón por intranet local. Todo funciona.

Los datos se sincronizan con el Ministerio cuando haya conexión
disponible según el modo configurado.

## Instalar (cuando se apruebe)

```bash
cp .env.template .env
# Editar: ANNOBON_SYNC_MODE, SYNC_API_TOKEN, DATABASE_URL
sudo bash instalar.sh
```

## Desarrollo local

```bash
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.template .env
python scripts/seed_db.py
python run.py
```

## Repos relacionados

- [`bioko-health-ministerio`](../bioko-health-ministerio)
- [`bioko-health-nodo-provincial`](../bioko-health-nodo-provincial)
- [`bioko-health-instalacion`](../bioko-health-instalacion)
