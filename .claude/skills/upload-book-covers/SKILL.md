# Upload Book Covers to Production

Skill para fazer upload em massa de capas de livros (experimento `new_cover_experiment`) para produção via Kubernetes pods.

## Uso

```bash
/upload-book-covers
```

## O que essa skill faz

Esta skill automatiza o processo completo de upload de capas de livros para o campo `new_cover_experiment` da tabela `books` em produção:

1. ✅ Copia imagens do local para o pod de produção
2. ✅ Valida que os livros existem no banco
3. ✅ Faz upload para S3 via Paperclip
4. ✅ Atualiza banco de dados com metadados
5. ✅ Gera URLs do CDN e Thumbor
6. ✅ Enfileira job de Blurhash automaticamente

## Pré-requisitos

### 1. Preparação das Imagens

As imagens devem estar nomeadas com o **ID do livro**:

```
16545.jpg  → Livro ID 16545
18590.jpg  → Livro ID 18590
62549.jpg  → Livro ID 62549
```

**Formatos suportados:** `.jpg`, `.jpeg`, `.png`, `.webp`

### 2. Acesso ao Cluster Kubernetes

```bash
# Verificar acesso
kubectl config use-context gke_min-b302a_southamerica-east1-a_api-production
kubectl get pods -l app=api
```

### 3. Script de Upload

O script deve estar em: `/Users/renatofilho/Projects/web/vendor/scripts/books/upload_new_cover_experiment.rb`

## Workflow Completo

### Passo 1: Obter Pod de Produção

```bash
# Switch para produção
kubectl config use-context gke_min-b302a_southamerica-east1-a_api-production

# Obter nome do pod
POD=$(kubectl get pods -l app=api --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD"
```

### Passo 2: Copiar Imagens para o Pod

**Opção A: Copiar todas as imagens (via tar - mais rápido)**

```bash
# Pasta local com imagens
IMAGES_DIR="/Users/renatofilho/Downloads/customs"

# Criar tarball
cd "$(dirname $IMAGES_DIR)"
tar -czf customs.tar.gz "$(basename $IMAGES_DIR)/"

# Copiar para pod
kubectl cp customs.tar.gz $POD:/tmp/customs.tar.gz

# Extrair no pod
kubectl exec $POD -- tar -xzf /tmp/customs.tar.gz -C /tmp/

# Verificar quantidade
kubectl exec $POD -- sh -c "ls /tmp/customs | wc -l"
# Exemplo: 320
```

**Opção B: Copiar uma imagem de teste**

```bash
# Teste com apenas 1 livro
kubectl exec $POD -- mkdir -p /tmp/customs
kubectl cp /Users/renatofilho/Downloads/customs/16545.jpg $POD:/tmp/customs/16545.jpg
kubectl exec $POD -- ls -lh /tmp/customs/
```

### Passo 3: Copiar Script de Upload

```bash
kubectl cp /Users/renatofilho/Projects/web/vendor/scripts/books/upload_new_cover_experiment.rb $POD:/tmp/upload_new_cover_experiment.rb

# Verificar
kubectl exec $POD -- ls -lh /tmp/upload_new_cover_experiment.rb
```

### Passo 4: Executar Dry-Run (Simulação)

```bash
kubectl exec $POD -- sh -c "cd /app && bundle exec rails runner /tmp/upload_new_cover_experiment.rb --directory /tmp/customs --environment production --dry-run"
```

**Output esperado:**

```
╔════════════════════════════════════════════════════════╗
║  📸 New Cover Experiment Upload Script                ║
╚════════════════════════════════════════════════════════╝

⚙️  Configuration

🔧 Loading Rails environment...
   ✅ Rails environment loaded (production)
   ✅ Database: ebdb

📂 Scanning directory for image files...
   ✅ Found 320 image files

📸 Total image files found: 320
Environment: production
Dry-run mode: YES (no changes will be made)

[Step 1] 🔍 Validating files and books...
   ✅ Book ID 16545 - "Your money or your life" (167.81 KB)
   ✅ Book ID 18590 - "The 4-Hour Workweek" (204.00 KB)
   ❌ Book ID 99999 not found in database
   ...

   Summary:
   • Books found: 318
   • Books not found: 2
   • Files skipped: 0

[Step 2] 🚀 Uploading covers...
   ⏭️  Dry-run mode: Simulating uploads

📊 Final Report:
   • Total files scanned: 320
   • Books found: 318
   • Uploaded: 318 (simulated)
   • Not found: 2
   • Failed: 0

📄 Report saved: /tmp/new_cover_experiment_upload_report_2026-02-12_19-03-56.json

✅ Dry-run completed successfully!
```

### Passo 5: Executar Upload REAL

**⚠️ ATENÇÃO: Isso fará alterações PERMANENTES em PRODUÇÃO!**

```bash
# Upload completo (todas as imagens)
kubectl exec $POD -- sh -c "cd /app && bundle exec rails runner /tmp/upload_new_cover_experiment.rb --directory /tmp/customs --environment production --no-dry-run --yes"
```

**Tempo estimado:** ~13-15 minutos para 320 imagens

**Output esperado:**

```
[Step 2] 🚀 Uploading covers...
[paperclip] saving books/books_new_cover_experiment/16545_16545.original.jpg
Enfileirando job para gerar Blurhash para Book#16545
   ⏳ Uploading book 16545... ✅ Success (2590ms, 167.81 KB)
   ⏳ Uploading book 18590... ✅ Success (2341ms, 204.00 KB)
   ...

   ✅ 318 books uploaded successfully

📊 Final Report:
   • Uploaded: 318
   • Failed: 0

✅ Upload completed successfully!
```

### Passo 6: Verificar Upload

**Verificar no banco de dados:**

```bash
kubectl exec $POD -- sh -c "PGPASSWORD=\$RDS_PASSWORD psql -h \$RDS_HOSTNAME -U \$RDS_USERNAME -d \$RDS_DB_NAME -c \"SELECT COUNT(*) FROM books WHERE new_cover_experiment_file_name IS NOT NULL;\""
```

**Verificar um livro específico:**

```bash
kubectl exec $POD -- sh -c "PGPASSWORD=\$RDS_PASSWORD psql -h \$RDS_HOSTNAME -U \$RDS_USERNAME -d \$RDS_DB_NAME -c \"SELECT id, title, new_cover_experiment_file_name, new_cover_experiment_file_size FROM books WHERE id = 16545;\""
```

**Verificar URLs geradas:**

```bash
kubectl exec $POD -- sh -c "cd /app && bundle exec rails runner \"
book = Book.find(16545)
puts 'Original: ' + book.new_cover_experiment.url(:original)
puts 'Thumb: ' + book.new_cover_experiment_thumb_image_url
puts 'Large: ' + book.new_cover_experiment_large_image_url
\""
```

**Testar URL no navegador:**

```bash
# Exemplo de URL gerada
https://cdn.12min.com/books/books_new_cover_experiment/16545_16545.original.jpg?1770923210
```

## Opções Avançadas

### Upload de Livros Específicos

```bash
# Apenas alguns IDs
kubectl exec $POD -- sh -c "cd /app && bundle exec rails runner /tmp/upload_new_cover_experiment.rb --directory /tmp/customs --book-ids 16545,18590,62549 --environment production --no-dry-run --yes"
```

### Upload em Lotes

```bash
# Lote 1: IDs 16545-16595 (50 livros)
kubectl exec $POD -- sh -c "cd /app && bundle exec rails runner /tmp/upload_new_cover_experiment.rb --directory /tmp/customs --book-ids 16545,16546,16547,...,16595 --environment production --no-dry-run --yes"

# Lote 2: IDs 18590-18640 (50 livros)
kubectl exec $POD -- sh -c "cd /app && bundle exec rails runner /tmp/upload_new_cover_experiment.rb --directory /tmp/customs --book-ids 18590,18591,...,18640 --environment production --no-dry-run --yes"
```

### Verificar Relatório JSON

```bash
# Ver relatório detalhado
kubectl exec $POD -- cat /tmp/new_cover_experiment_upload_report_2026-02-12_19-06-53.json

# Exemplo de relatório
{
  "timestamp": "2026-02-12T19:06:53-03:00",
  "environment": "production",
  "dry_run": false,
  "total_files": 320,
  "books_uploaded": 318,
  "books_not_found": 2,
  "books_failed": 0,
  "uploaded_book_ids": [16545, 18590, ...],
  "not_found": [
    { "book_id": 99999, "file": "/tmp/customs/99999.jpg" }
  ]
}
```

## Estrutura de Dados

### Tabela `books`

Colunas criadas pelo upload:

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `new_cover_experiment_file_name` | `varchar` | Nome do arquivo (ex: `16545.jpg`) |
| `new_cover_experiment_content_type` | `varchar` | MIME type (ex: `image/jpeg`) |
| `new_cover_experiment_file_size` | `integer` | Tamanho em bytes |
| `new_cover_experiment_updated_at` | `timestamp` | Data/hora do upload |

### URLs Geradas

O modelo `Book` gera automaticamente 4 tipos de URLs via Thumbor:

1. **Original** (S3): `https://cdn.12min.com/books/books_new_cover_experiment/16545_16545.original.jpg`
2. **Thumb** (150x150): `https://images.12min.com/.../150x150/...`
3. **Medium** (570x368): `https://images.12min.com/.../570x368/...`
4. **Large** (630x900): `https://images.12min.com/.../630x900/...`
5. **Cover** (840x1600): `https://images.12min.com/.../840x1600/...`

## Troubleshooting

### Erro: "Book ID not found"

**Causa:** ID da imagem não existe no banco de dados

**Solução:** Normal para IDs inexistentes. Verifique o relatório JSON para ver quais IDs não foram encontrados.

### Erro: "Directory not found"

**Causa:** Pasta `/tmp/customs` não existe no pod

**Solução:**
```bash
kubectl exec $POD -- mkdir -p /tmp/customs
kubectl cp /path/to/images/* $POD:/tmp/customs/
```

### Erro: "Rails not loaded"

**Causa:** Script não está sendo executado via `rails runner`

**Solução:** Sempre use:
```bash
bundle exec rails runner /tmp/upload_new_cover_experiment.rb
```

### Upload lento

**Causa:** Processamento sequencial (1 imagem por vez)

**Expectativa:**
- 1 livro = ~2-3 segundos
- 320 livros = ~13-15 minutos total

### Imagem não aparece no CDN

**Causa:** Cache do CDN ou Thumbor

**Solução:**
```bash
# Aguardar 1-2 minutos
# Ou adicionar cache buster na URL: ?v=timestamp
```

## Segurança

- ✅ **Dry-run é padrão** - Não faz alterações sem `--no-dry-run`
- ✅ **Confirmação obrigatória** em produção (usar `--yes` para pular)
- ✅ **Relatórios auditáveis** salvos em `/tmp/`
- ✅ **Não sobrescreve** capas originais (`cover`, `custom_cover`)
- ⚠️ **Backup recomendado** antes de uploads em massa

## Performance

| Métrica | Valor |
|---------|-------|
| Upload por livro | ~2-3 segundos |
| 50 livros | ~2-3 minutos |
| 100 livros | ~5-7 minutos |
| 320 livros | ~13-15 minutos |

## Arquivos Relacionados

- **Script**: `/Users/renatofilho/Projects/web/vendor/scripts/books/upload_new_cover_experiment.rb`
- **Modelo**: `/Users/renatofilho/Projects/web/app/models/book.rb` (linhas 87-90)
- **README**: `/Users/renatofilho/Projects/web/vendor/scripts/books/UPLOAD_NEW_COVER_EXPERIMENT_README.md`

## Exemplo Completo (Teste com 1 Livro)

```bash
# 1. Configurar ambiente
POD=$(kubectl get pods -l app=api --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')

# 2. Copiar imagem de teste
kubectl exec $POD -- mkdir -p /tmp/customs
kubectl cp /Users/renatofilho/Downloads/customs/16545.jpg $POD:/tmp/customs/16545.jpg

# 3. Copiar script
kubectl cp /Users/renatofilho/Projects/web/vendor/scripts/books/upload_new_cover_experiment.rb $POD:/tmp/upload_new_cover_experiment.rb

# 4. Dry-run
kubectl exec $POD -- sh -c "cd /app && bundle exec rails runner /tmp/upload_new_cover_experiment.rb --directory /tmp/customs --environment production --dry-run"

# 5. Upload real
kubectl exec $POD -- sh -c "cd /app && bundle exec rails runner /tmp/upload_new_cover_experiment.rb --directory /tmp/customs --environment production --no-dry-run --yes"

# 6. Verificar
kubectl exec $POD -- sh -c "PGPASSWORD=\$RDS_PASSWORD psql -h \$RDS_HOSTNAME -U \$RDS_USERNAME -d \$RDS_DB_NAME -c \"SELECT id, title, new_cover_experiment_file_name FROM books WHERE id = 16545;\""

# 7. Testar URL
curl -I "https://cdn.12min.com/books/books_new_cover_experiment/16545_16545.original.jpg?$(date +%s)"
```

## Changelog

- **2026-02-12**: Skill criada com processo completo de upload em produção
