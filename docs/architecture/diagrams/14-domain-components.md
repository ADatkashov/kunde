# Domain Components (фактическое состояние, C4 level 3)

В отличие от диаграмм 01–13 (целевое состояние) эта диаграмма показывает **реальные** зависимости на 2026-11-24 между модулями `:app` — по данным [матрицы зависимостей](../domain-dependency-matrix.md). Стрелка — «зависит от» (импорт или SQL в таблицы владельца). Контекст и контейнеры — [01](01-system-context.md), [02](02-container-architecture.md).

```mermaid
flowchart LR
  subgraph apps[Flutter apps]
    C[Consumer]; P[Partner]; E[Executor]; A[Admin]
  end
  apps --> API
  subgraph API[kunde-api: единый deployable]
    subgraph core[Ядро]
      identity[identity+auth]; partners[partners+catalog]; platform[[platform: security, errors, outbox, geo, placement]]
    end
    admin[admin]
    subgraph food_family[food family]
      food; groceries
    end
    subgraph mobility[mobility]
      rides; delivery
    end
    subgraph booking_family[booking family]
      booking; beauty; homeservices; health; auto
    end
    leisure_events[leisure + events]
    education; support
    maps[maps adapter]
  end
  API --> DB[(PostgreSQL: одна БД, владение по префиксам)]
  maps --> KM[kunde-maps: отдельный сервис]
  admin -.->|44 SQL + 9 импортов| food_family & leisure_events & booking_family & partners
  groceries --> food
  food -.->|обратно| groceries
  rides <-.-> delivery
  booking_family -->|намеренно| booking
  booking -.->|обратно: auto/health| booking_family
  partners -.->|демо-сид| food_family & booking_family
  food_family & mobility & booking_family & leisure_events & education --> partners
  food_family & mobility & booking_family & leisure_events & education & partners --> identity
```

Пунктир — зависимости, которые мешают выделению (см. узел циклов в матрице).
