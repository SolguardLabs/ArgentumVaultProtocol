# Security Policy

ArgentumVaultProtocol mantiene un modelo de seguridad centrado en accounting de
vaults por epoch, liquidez disponible, reservas internas y ejecucion controlada
por keepers.

## Scope

Estan en alcance:

- contratos Vyper en `src/`;
- tests Python en `tests/`;
- scripts reproducibles en `scripts/`;
- configuracion de CI.

Fuera de scope:

- dependencias de desarrollo;
- `.venv`;
- artefactos generados por cache local.

## Invariantes Esperadas

- Los deposits deben emitir shares contra el precio interno vigente.
- Las requests de withdrawal deben respetar el delay de epoch configurado.
- La ejecucion por lotes no debe exceder la liquidez disponible.
- Las reservas internas deben mantenerse por encima de los buffers definidos.
- Los reports de perdida deben reconciliar NAV, shares y obligaciones pendientes.
- Las rutas de keeper no deben saltarse limites de batch ni ventanas operativas.

## Reporting

Los reportes deben incluir:

- resumen;
- impacto;
- pasos de reproduccion;
- root cause;
- parche o mitigacion sugerida.
