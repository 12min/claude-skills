# Timer Command

Inicia um timer regressivo com exibição em tempo real e alerta sonoro ao final.

## Uso

```bash
/timer <tempo>
/timer 5m          # 5 minutos
/timer 30s         # 30 segundos
/timer 2h30m       # 2 horas e 30 minutos
/timer 10         # 10 segundos (sem unidade)
```

## Formato de Entrada

- `m` - minutos (ex: `5m`)
- `s` - segundos (ex: `30s`)
- `h` - horas (ex: `1h`)
- Combinações: `1h30m`, `2h15m30s`
- Número sem unidade = segundos

## Exibição

O timer exibe em tempo real no formato `MM:SS`:
```
5:00
4:59
4:58
...
0:01
0:00
```

Quando o timer termina:
- Exibe "⏰ Tempo finalizado!"
- Toca um som de alerta
- Retorna ao prompt

## Exemplos

```bash
/timer 5m          # Timer de 5 minutos
/timer 1m30s       # Timer de 1 minuto e 30 segundos
/timer 45s         # Timer de 45 segundos
/timer 2h          # Timer de 2 horas
```

## Atalhos

- `Ctrl+C` para parar o timer
