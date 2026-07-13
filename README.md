# ArgentumVaultProtocol

![banner](./assets/banner.png)

ArgentumVaultProtocol es un protocolo de vault en Vyper para stablecoins. Modela
shares, retiros por epochs, liquidez libre, reservas internas y capital asignado
a una estrategia controlada.

El objetivo del repositorio es validar la contabilidad de solicitudes de
withdrawal que se crean en una epoch y se ejecutan posteriormente por lotes.

## Superficie Del Protocolo

- `ArgentumVault`: vault principal con depositos, shares ERC20-like, requests de
  withdrawal, ejecucion por epochs, reserva interna y reports de perdida.
- `MockStablecoin`: stablecoin de 6 decimales para pruebas.
- `MockStrategy`: estrategia simulada que recibe liquidez, devuelve capital o
  materializa perdidas.
- `ArgentumReservePolicy`: calculos y limites de reserva.
- `ArgentumRiskController`: limites de asignacion, perdidas y presion de cola.
- `ArgentumKeeperCoordinator`: programacion de trabajos de keeper por epoch.
- `ArgentumLens`: vistas agregadas para dashboards y auditoria.
- `ArgentumWithdrawalRouter`: router delegado para crear requests.
- `accounting/` y `scenario/`: material auxiliar para analizar NAV, epochs y
  escenarios economicos.

## Layout

```text
src/
  accounting/
  core/
  governance/
  interfaces/
  libraries/
  mocks/
  periphery/
  scenario/
tests/
scripts/
```

## Requisitos

- Python 3.11 o superior.
- Vyper 0.4.3.
- titanoboa 0.2.8 o superior.
- pytest.

## Comandos

```bash
python -m venv .venv
./.venv/Scripts/python -m pip install -r requirements.txt
./.venv/Scripts/pytest
```

En PowerShell tambien puedes usar:

```powershell
.\scripts\tests.ps1
```

El flujo completo de CI compila los contratos Vyper y ejecuta la suite:

```bash
bash scripts/ci.sh
```

## Estado

Los tests Python despliegan los contratos con titanoboa y validan:

- depositos y mint de shares;
- reserva interna objetivo;
- request de withdrawal con delay de epoch;
- ejecucion por lotes;
- cambios de liquidez por asignacion, retorno y perdida;
- escenario minimo de cola antes de perdida y ejecucion posterior.

El repositorio esta preparado como target de revision de seguridad de logica
economica y como base reproducible para validar cambios de accounting,
liquidez y ejecucion por epochs.
