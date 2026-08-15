# Modelo económico

## Unidades

Los activos usan la precisión del token subyacente; los ratios usan `10_000`
puntos básicos y el PPS usa `10¹⁸`. No deben mezclarse cantidades normalizadas
con cantidades nativas en una misma operación.

## Contabilidad del vault

```text
A = F + R + S
PPS = A · WAD / Q
shares(deposit) = deposit · Q / A
assets(shares) = shares · A / Q
```

Donde `A` son activos totales, `F` liquidez libre, `R` reserva, `S` capital de
estrategia y `Q` oferta de shares. Cuando `Q = 0`, la relación inicial es 1:1.

## Reserva

```text
target(A) = max(floor, A · target_bps / 10_000)
liquid = F + R
coverage = min(10_000, liquid · 10_000 / pending)
```

Ejemplo: con `A = 5.000.000`, objetivo `20 %` y floor `250.000`, la reserva
objetivo es `1.000.000`. Si la cola pendiente es `600.000` y la liquidez total
es `900.000`, la cobertura es `10.000 bps`; aun así el keeper protege el buffer
definido antes de calcular el importe procesable.

## Motor de estrés

El motor aplica dos transformaciones a una estrategia de saldo `S`:

```text
loss = S · loss_bps / 10_000
recall = (S - loss) · recall_bps / 10_000
A' = A - loss
L' = F + R + recall
```

Después calcula shortfall de cola, reserva posterior, PPS proyectado y una
severidad entre `0` y `3`. Las entradas deben satisfacer `A = F + R + S`; una
vista incoherente se rechaza en vez de producir una recomendación.

```mermaid
flowchart LR
    I["Snapshot contable"] --> L["Aplicar pérdida"]
    L --> C["Aplicar recall"]
    C --> Q["Atender presión de cola"]
    Q --> R["Reserva posterior"]
    R --> M["PPS, ratios y severidad"]
```

## Política de lotes

El planificador del cliente limita el lote por elementos restantes, cap del
protocolo y presupuesto de gas:

```text
batch = min(remaining, protocol_cap, gas_budget / gas_per_item)
```

Las proyecciones son deterministas, no una autorización para ejecutar. El
keeper debe volver a leer el estado en el bloque de envío y aplicar límites de
deslizamiento operacional a cualquier acción externa de estrategia.
