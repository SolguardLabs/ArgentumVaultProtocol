# Integración

## Cliente Python

`ArgentumClient` acepta cualquier objeto que implemente las lecturas del vault.
No gestiona claves ni envía transacciones. Su propósito es normalizar snapshots,
mapear épocas y preparar parámetros conservadores para el keeper.

```python
from client import ArgentumClient

client = ArgentumClient(vault)
state = client.snapshot()
if not state.reconciles():
    raise RuntimeError("accounting mismatch")

epoch = client.epoch(state.current_epoch)
batch = client.suggested_batch(
    remaining_items=epoch.remaining_items,
    gas_budget=4_000_000,
    gas_per_item=50_000,
)
```

## Decimales

Las cantidades enviadas a contratos usan unidades nativas. Para una stablecoin
de seis decimales, `125,50` se expresa como `125_500_000`. El PPS permanece en
WAD aunque el activo use otra precisión.

## Confirmaciones

Una aplicación debe esperar la política de confirmación de su red antes de
mostrar un depósito o una liquidación como final. Los eventos sirven para
indexación, pero las decisiones económicas deben volver a leer almacenamiento.

## Errores esperados

| Error | Acción del cliente |
| --- | --- |
| `CAPACITY` | Reducir o dividir el depósito |
| `REQUEST_CAP` | Dividir shares en solicitudes válidas |
| `FUTURE_EPOCH` | Esperar madurez |
| `INSUFFICIENT_LIQUIDITY` | Programar recall y recalcular lote |
| `DEPOSITS_PAUSED` | No reintentar automáticamente |
| `REQUESTS_PAUSED` | Mostrar estado operativo |
| `ONLY_KEEPER` | Corregir identidad firmante |

No se recomienda reintentar ciegamente una transacción revertida: el cliente
debe clasificar el error y refrescar el estado.
