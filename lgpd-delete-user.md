# LGPD User Deletion

Execute a conformidade LGPD de exclusão permanente de conta de usuário. Este comando orquestra a deleção sequencial de dados do usuário no Web Backend (Rails), Billing Service (Node.js), ActiveCampaign e OneSignal.

**Invocado como:** `/lgpd-delete-user <email>`

**Sistemas cobertos:** Web Backend (Rails), Billing Service, ActiveCampaign, Amplitude, OneSignal, Adjust

---

## FASE 0 — Validação e Confirmação

O email a ser deletado está em `$ARGUMENTS`.

1. Se nenhum email foi fornecido em `$ARGUMENTS`, abortar com a mensagem:
   ```
   Erro: Informe o email do usuário. Uso: /lgpd-delete-user <email>
   ```

2. Antes de qualquer ação, exibir um aviso claro e pedir confirmação explícita do usuário:
   ```
   ⚠️  ATENÇÃO: OPERAÇÃO IRREVERSÍVEL ⚠️

   Você está prestes a excluir permanentemente todos os dados do usuário:
   Email: <email>

   Esta operação:
   • Deleta dados no Web Backend (Rails) e no Billing Service
   • Remove contato do ActiveCampaign
   • Remove usuário do OneSignal (push notifications)
   • Solicita esquecimento de dispositivos no Adjust (GDPR)
   • NÃO pode ser desfeita
   • É para conformidade com LGPD (Lei nº 13.709/2018)

   Digite "sim" para confirmar a exclusão:
   ```

3. Use `AskUserQuestion` para coletar a confirmação. Se a resposta não for "sim", abortar sem realizar nenhuma ação.

---

## FASE 1 — Localizar Usuário no Web Backend (Rails)

Execute via Bash (diretório: `/Users/renatofilho/Projects/web`):

```bash
cd /Users/renatofilho/Projects/web && docker compose exec app bundle exec rails runner "
  user = User.find_by(email: '$ARGUMENTS')
  if user
    puts \"USER_ID:#{user.id}\"
    puts \"USERNAME:#{user.username || user.name || 'N/A'}\"
    puts \"STATUS:#{user.status}\"
    puts \"CREATED_AT:#{user.created_at}\"
    puts \"PROVIDER:#{user.provider || 'email'}\"
    puts \"PHONE:#{user.phone || 'N/A'}\"
  else
    puts 'USUARIO_NAO_ENCONTRADO'
  end
"
```

- Se a saída contiver `USUARIO_NAO_ENCONTRADO`: abortar com mensagem `Usuário com email '$ARGUMENTS' não encontrado no sistema. Nenhuma ação realizada.`
- Extrair o `user_id` da linha `USER_ID:XXXXX`
- Exibir as informações do usuário encontrado para confirmação visual

---

## FASE 2 — Deletar em Sistemas Externos (ActiveCampaign + OneSignal)

As chamadas de API são feitas via `kubectl exec` no pod de produção, pois as variáveis de ambiente (`AC_API_TOKEN`, `ONE_SIGNAL_API_KEY`, etc.) estão disponíveis lá. Não é necessário curl — usa-se Ruby `net/http`, que já está presente no pod.

**Pré-requisito:** obter o nome do pod em execução:

```bash
kubectl config use-context gke_min-b302a_southamerica-east1-a_api-production
POD=$(kubectl get pods -l app=api -o jsonpath='{.items[0].metadata.name}')
```

### 2a — ActiveCampaign: remover contato

Buscar o contato por email e deletar pelo ID encontrado:

```bash
kubectl exec $POD -- sh -c '
ruby -e "
require \"net/http\"; require \"uri\"; require \"json\"
base_uri = URI.parse(ENV[\"AC_API_URL\"])
base = \"#{base_uri.scheme}://#{base_uri.host}\"
token = ENV[\"AC_API_TOKEN\"]
email = URI.encode_www_form_component(\"EMAIL_PLACEHOLDER\")

# 1. Buscar contato por email
search_uri = URI.parse(\"#{base}/api/3/contacts?email=#{email}&limit=5\")
req = Net::HTTP::Get.new(search_uri)
req[\"Api-Token\"] = token
res = Net::HTTP.start(search_uri.host, search_uri.port, use_ssl: true) { |h| h.request(req) }
data = JSON.parse(res.body)
total = data.dig(\"meta\", \"total\").to_i

if total == 0
  puts \"AC_NOT_FOUND:contato nao encontrado no ActiveCampaign\"
else
  data[\"contacts\"].each do |contact|
    cid = contact[\"id\"]
    cemail = contact[\"email\"]
    # 2. Deletar contato
    del_uri = URI.parse(\"#{base}/api/3/contacts/#{cid}\")
    del_req = Net::HTTP::Delete.new(del_uri)
    del_req[\"Api-Token\"] = token
    del_res = Net::HTTP.start(del_uri.host, del_uri.port, use_ssl: true) { |h| h.request(del_req) }
    if del_res.code == \"200\"
      puts \"AC_DELETED:#{cemail} (id=#{cid})\"
    else
      puts \"AC_ERROR:#{cemail} id=#{cid} http=#{del_res.code} body=#{del_res.body[0..200]}\"
    end
  end
end
"
'
```

Substituir `EMAIL_PLACEHOLDER` pelo email do usuário.

- `AC_NOT_FOUND`: logar e continuar (usuário pode nunca ter entrado no AC)
- `AC_DELETED`: sucesso
- `AC_ERROR`: logar e continuar, anotar para verificação manual

### 2b — Amplitude: solicitar deleção GDPR

A Amplitude GDPR API aceita `user_ids` (que podem ser tanto o user_id numérico quanto o email, já que o Rails envia eventos com `user_id = email`). A deleção não é imediata — a Amplitude processa em até 30 dias, mas confirma o recebimento do pedido.

**Variáveis:** `AMPLITUDE_SECRET_KEY` (no Secret `12min-credentials`) + API key hardcoded `fa4b0a4e06cd1e585aa882324575e119`.

```bash
kubectl exec $POD -- sh -c '
ruby -e "
require \"net/http\"; require \"uri\"; require \"json\"; require \"base64\"
api_key = \"fa4b0a4e06cd1e585aa882324575e119\"
secret_key = ENV[\"AMPLITUDE_SECRET_KEY\"]
credentials = Base64.strict_encode64(\"#{api_key}:#{secret_key}\")

# Enviar pedido de deleção para ambos os identificadores:
# - user_id numérico (usado pelo billing)
# - email (usado pelo Rails: lib/amplitude.rb)
body = {
  user_ids: [\"USER_ID_PLACEHOLDER\", \"EMAIL_PLACEHOLDER\"],
  requester: \"lgpd-delete-user-command\"
}.to_json

uri = URI.parse(\"https://amplitude.com/api/2/deletions/users\")
req = Net::HTTP::Post.new(uri)
req[\"Authorization\"] = \"Basic #{credentials}\"
req[\"Content-Type\"] = \"application/json\"
req.body = body

res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
puts \"Amplitude GDPR HTTP: #{res.code}\"
data = JSON.parse(res.body) rescue {}
if res.code == \"200\"
  puts \"AMPLITUDE_QUEUED:pedido de delecao registrado\"
  puts \"  job_id: #{data[\"id\"]}\" if data[\"id\"]
  puts \"  status: #{data[\"status\"]}\" if data[\"status\"]
  puts \"  (processado em ate 30 dias pela Amplitude)\"
else
  puts \"AMPLITUDE_ERROR:http=#{res.code} body=#{res.body[0..300]}\"
end
"
'
```

Substituir `USER_ID_PLACEHOLDER` pelo user_id numérico e `EMAIL_PLACEHOLDER` pelo email do usuário.

- `AMPLITUDE_QUEUED`: sucesso — deleção agendada
- `AMPLITUDE_ERROR`: logar e continuar; verificar manualmente em https://analytics.amplitude.com

### 2c — OneSignal: remover usuário

O OneSignal armazena o usuário pelo `external_id` (= `user_id` do Rails). A User Management API permite deletar por esse identificador:

```bash
kubectl exec $POD -- sh -c '
ruby -e "
require \"net/http\"; require \"uri\"; require \"json\"
app_id = ENV[\"ONE_SIGNAL_APP_ID\"]
api_key = ENV[\"ONE_SIGNAL_API_KEY\"]
user_id = \"USER_ID_PLACEHOLDER\"

# 1. Verificar se o usuário existe
get_uri = URI.parse(\"https://onesignal.com/api/v1/apps/#{app_id}/users/by/external_id/#{user_id}\")
req = Net::HTTP::Get.new(get_uri)
req[\"Authorization\"] = \"Basic #{api_key}\"
res = Net::HTTP.start(get_uri.host, get_uri.port, use_ssl: true) { |h| h.request(req) }

if res.code == \"404\"
  puts \"OS_NOT_FOUND:usuario nao encontrado no OneSignal\"
elsif res.code == \"200\"
  # 2. Deletar usuário
  del_uri = URI.parse(\"https://onesignal.com/api/v1/apps/#{app_id}/users/by/external_id/#{user_id}\")
  del_req = Net::HTTP::Delete.new(del_uri)
  del_req[\"Authorization\"] = \"Basic #{api_key}\"
  del_res = Net::HTTP.start(del_uri.host, del_uri.port, use_ssl: true) { |h| h.request(del_req) }
  if del_res.code == \"200\"
    puts \"OS_DELETED:external_id=#{user_id}\"
  else
    puts \"OS_ERROR:http=#{del_res.code} body=#{del_res.body[0..200]}\"
  end
else
  puts \"OS_ERROR:get_http=#{res.code} body=#{res.body[0..200]}\"
end
"
'
```

Substituir `USER_ID_PLACEHOLDER` pelo `user_id` da Fase 1.

- `OS_NOT_FOUND`: logar e continuar (usuário nunca fez login no app ou tokens já expirados)
- `OS_DELETED`: sucesso — todos os dispositivos vinculados ao external_id são removidos
- `OS_ERROR`: logar e continuar, anotar para verificação manual

### 2d — Adjust: esquecer dispositivos (GDPR)

O Adjust armazena dispositivos do usuário na tabela `adjust_headers` do Billing DB (campos `adid`, `gps_adid`, `idfa`). Esta fase deve rodar **antes** da Fase 3, pois a Fase 3 deleta esses registros.

Credenciais hardcoded em `billing/src/environment.ts`:
- `ADJUST_APP_TOKEN`: `8q9lgl4fa4u8`
- `ADJUST_S2S_TOKEN`: `4a513eea6b7635c149eb055c6b77f6f5`

Execute via Bash (diretório: `/Users/renatofilho/Projects/billing`):

```bash
cd /Users/renatofilho/Projects/billing && docker compose exec billing node -e "
const https = require('https');
const querystring = require('querystring');
const { Sequelize } = require('sequelize');

const dbUrl = process.env.DATABASE_URL || process.env.BILLING_DATABASE_URL;
const sequelize = new Sequelize(dbUrl, { logging: false, dialect: 'postgres' });

const userId = USER_ID_PLACEHOLDER;
const APP_TOKEN = '8q9lgl4fa4u8';
const S2S_TOKEN = '4a513eea6b7635c149eb055c6b77f6f5';

async function forgetDevice(adid) {
  return new Promise((resolve) => {
    const body = querystring.stringify({ app_token: APP_TOKEN, adid });
    const req = https.request({
      hostname: 'gdpr.adjust.com',
      path: '/forget_device',
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + S2S_TOKEN,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(body),
      }
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          console.log('ADJUST_FORGOTTEN:adid=' + adid);
        } else {
          console.log('ADJUST_ERROR:adid=' + adid + ' http=' + res.statusCode + ' body=' + data.substring(0, 200));
        }
        resolve(null);
      });
    });
    req.on('error', e => { console.log('ADJUST_ERROR:' + e.message); resolve(null); });
    req.write(body);
    req.end();
  });
}

async function run() {
  try {
    await sequelize.authenticate();
    const [rows] = await sequelize.query(
      'SELECT adid FROM adjust_headers WHERE user_id = :userId AND adid IS NOT NULL',
      { replacements: { userId } }
    );

    if (rows.length === 0) {
      console.log('ADJUST_NOT_FOUND:nenhum device encontrado para user_id=' + userId);
    } else {
      for (const row of rows) {
        await forgetDevice(row.adid);
      }
      console.log('ADJUST_DONE:' + rows.length + ' dispositivo(s) processado(s)');
    }
  } catch(e) {
    console.log('ADJUST_ERROR:' + e.message);
  } finally {
    await sequelize.close();
  }
}

run();
"
```

Substituir `USER_ID_PLACEHOLDER` pelo `user_id` da Fase 1.

- `ADJUST_NOT_FOUND`: logar e continuar — usuário nunca usou o app ou não tinha tracking habilitado
- `ADJUST_FORGOTTEN`: sucesso por dispositivo
- `ADJUST_DONE`: todos os dispositivos processados
- `ADJUST_ERROR`: logar e continuar, anotar para verificação manual em https://dash.adjust.com → Data Privacy → Forget Device

### 2e — SendGrid: suppression global

Adiciona o email à lista de supressão global do SendGrid, impedindo qualquer envio futuro para esse endereço.

**Variável:** `SENDGRID_TOKEN` (disponível no pod de produção).

```bash
kubectl exec $POD -- sh -c '
ruby -e "
require \"net/http\"; require \"uri\"; require \"json\"
token = ENV[\"SENDGRID_TOKEN\"]
email = \"EMAIL_PLACEHOLDER\"

uri = URI.parse(\"https://api.sendgrid.com/v3/asm/suppressions/global\")
req = Net::HTTP::Post.new(uri)
req[\"Authorization\"] = \"Bearer #{token}\"
req[\"Content-Type\"] = \"application/json\"
req.body = { recipient_emails: [email] }.to_json

res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
if res.code == \"201\"
  puts \"SG_SUPPRESSED:#{email}\"
else
  puts \"SG_ERROR:http=#{res.code} body=#{res.body[0..200]}\"
end
"
'
```

Substituir `EMAIL_PLACEHOLDER` pelo email do usuário.

- `SG_SUPPRESSED`: sucesso — email bloqueado para futuros envios
- `SG_ERROR`: logar e continuar, verificar manualmente em https://app.sendgrid.com/suppressions/global_unsubscribes

### 2f — RudderStack: deletar eventos no BigQuery

Todos os eventos do RudderStack são espelhados no BigQuery (dataset `rudderstack`, projeto `min-b302a`). São ~147 tabelas com coluna `user_id`. Algumas têm também coluna `email` diretamente.

**Importante:** O BigQuery MCP só tem permissão de leitura. Os DELETEs devem ser executados via `bq` CLI (usa credenciais do `gcloud`).

**Passo 1 — Dry run: identificar tabelas com dados**

Use `mcp__bigquery__execute_sql` para verificar quais tabelas têm registros antes de deletar:

```sql
CREATE TEMP TABLE _counts (tabela STRING, linhas INT64);

FOR tbl IN (
  SELECT DISTINCT table_name
  FROM `rudderstack`.INFORMATION_SCHEMA.COLUMNS
  WHERE column_name = 'user_id'
    AND table_name NOT LIKE '%_view'
  ORDER BY table_name
)
DO
  EXECUTE IMMEDIATE FORMAT(
    "INSERT INTO _counts SELECT '%s', COUNT(*) FROM `rudderstack`.`%s` WHERE CAST(user_id AS STRING) = 'USER_ID_PLACEHOLDER'",
    tbl.table_name,
    tbl.table_name
  );
END FOR;

SELECT tabela, linhas FROM _counts WHERE linhas > 0 ORDER BY linhas DESC;
```

**Passo 2 — Executar DELETEs via `bq` CLI**

Para cada tabela com dados retornada no dry run, execute via Bash:

```bash
# Deletar por user_id em cada tabela com dados
bq query --use_legacy_sql=false --project_id=min-b302a \
  "DELETE FROM \`rudderstack.NOME_DA_TABELA\` WHERE CAST(user_id AS STRING) = 'USER_ID_PLACEHOLDER'"
```

Para tabelas que também têm coluna `email` (como `identifies`, `sign_up`, `logged_in`, `lead`, `users`):

```bash
bq query --use_legacy_sql=false --project_id=min-b302a \
  "DELETE FROM \`rudderstack.NOME_DA_TABELA\` WHERE email = 'EMAIL_PLACEHOLDER'"
```

Substituir `USER_ID_PLACEHOLDER` pelo `user_id` numérico, `EMAIL_PLACEHOLDER` pelo email e `NOME_DA_TABELA` por cada tabela com dados.

- Cada comando retorna `Number of affected rows: N` — logar por tabela
- Se retornar 0 affected rows: normal, nenhum dado encontrado
- Se retornar erro de permissão: verificar autenticação com `gcloud auth list`
- Ao final logar `BQ_DONE:N tabelas, X linhas deletadas`

### 2g — Twilio: deletar histórico de SMS

O usuário pode ter telefone registrado no campo `phone` da tabela `users` (capturado na Fase 1). Se `PHONE` for `N/A`, pular esta fase.

**Variáveis:** `TWILIO_ACCOUNT_SID` + `TWILIO_AUTH_TOKEN` (disponíveis no pod de produção).

Busca todas as mensagens enviadas **para** e **do** número do usuário e as deleta individualmente.

```bash
kubectl exec $POD -- sh -c '
ruby -e "
require \"net/http\"; require \"uri\"; require \"json\"; require \"base64\"

phone = \"PHONE_PLACEHOLDER\"
account_sid = ENV[\"TWILIO_ACCOUNT_SID\"]
auth_token  = ENV[\"TWILIO_AUTH_TOKEN\"]
credentials = Base64.strict_encode64(\"#{account_sid}:#{auth_token}\")

def twilio(method, path, credentials)
  uri = URI.parse(\"https://api.twilio.com#{path}\")
  req = method == \"DELETE\" ? Net::HTTP::Delete.new(uri) : Net::HTTP::Get.new(uri)
  req[\"Authorization\"] = \"Basic #{credentials}\"
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
end

deleted = 0
errors  = 0

[\"To\", \"From\"].each do |dir|
  page = \"/2010-04-01/Accounts/#{account_sid}/Messages.json?#{dir}=#{URI.encode_www_form_component(phone)}&PageSize=100\"
  loop do
    res  = twilio(\"GET\", page, credentials)
    data = JSON.parse(res.body)
    msgs = data[\"messages\"] || []
    break if msgs.empty?
    msgs.each do |msg|
      del = twilio(\"DELETE\", \"/2010-04-01/Accounts/#{account_sid}/Messages/#{msg[\"sid\"]}\", credentials)
      del.code == \"204\" ? deleted += 1 : (errors += 1; puts \"TWILIO_ERROR:sid=#{msg[\"sid\"]} http=#{del.code}\")
    end
    next_page = data[\"next_page_uri\"]
    break if next_page.nil? || next_page.empty?
    page = next_page
  end
end

if deleted > 0
  puts \"TWILIO_DELETED:#{deleted} mensagem(ns) deletada(s)\"
elsif errors == 0
  puts \"TWILIO_NOT_FOUND:nenhuma mensagem encontrada para #{phone}\"
end
"
'
```

Substituir `PHONE_PLACEHOLDER` pelo valor de `PHONE` capturado na Fase 1.

- Se `PHONE` for `N/A`: pular esta fase e logar `TWILIO_SKIPPED:usuário sem telefone cadastrado`
- `TWILIO_NOT_FOUND`: logar e continuar — usuário nunca recebeu SMS
- `TWILIO_DELETED`: sucesso
- `TWILIO_ERROR`: logar SID e continuar, verificar manualmente no Twilio Console

---

## FASE 3 — Deletar Dados no Billing Service (Node.js)

**Nota LGPD importante:** Os registros de `v2_receipts` e `v2_invoices` contêm dados fiscais e devem ser **anonimizados** (não deletados) por requisito de retenção de 7 anos. Informar o usuário sobre isso antes de executar.

Execute via Bash (diretório: `/Users/renatofilho/Projects/billing`):

```bash
cd /Users/renatofilho/Projects/billing && docker compose exec billing node -e "
const { Sequelize, DataTypes } = require('sequelize');

// Carregar configuração do banco
const dbUrl = process.env.DATABASE_URL || process.env.BILLING_DATABASE_URL;
const sequelize = new Sequelize(dbUrl, { logging: false, dialect: 'postgres' });

const userId = parseInt('USER_ID_PLACEHOLDER');
const userIdStr = 'USER_ID_PLACEHOLDER';

async function deleteUserData() {
  const results = {};

  try {
    await sequelize.authenticate();

    // 1. AdjustHeader
    try {
      const [r] = await sequelize.query(
        'DELETE FROM adjust_headers WHERE user_id = :userId RETURNING id',
        { replacements: { userId }, type: sequelize.QueryTypes.SELECT }
      );
      results.adjust_headers = r ? 1 : 0;
      const [count] = await sequelize.query(
        'SELECT COUNT(*) as n FROM adjust_headers WHERE user_id = :userId RETURNING *',
        { replacements: { userId } }
      );
      const [deleted] = await sequelize.query(
        'DELETE FROM adjust_headers WHERE user_id = :userId',
        { replacements: { userId } }
      );
      console.log('adjust_headers: deleted');
    } catch(e) { console.log('adjust_headers: ' + (e.message.includes('exist') ? 'tabela nao existe' : e.message)); }

    // 2. TenjinHeader
    try {
      await sequelize.query('DELETE FROM tenjin_headers WHERE user_id = :userId', { replacements: { userId } });
      console.log('tenjin_headers: deleted');
    } catch(e) { console.log('tenjin_headers: ' + (e.message.includes('exist') ? 'tabela nao existe' : e.message)); }

    // 3. Anonimizar v2_receipts (retencao fiscal 7 anos)
    try {
      await sequelize.query(
        \`UPDATE v2_receipts SET
          receipt = 'LGPD_DELETED',
          updated_at = NOW()
        WHERE invoice_id IN (SELECT id FROM v2_invoices WHERE user_id = :userId)\`,
        { replacements: { userId } }
      );
      console.log('v2_receipts: anonimizado (retencao fiscal)');
    } catch(e) { console.log('v2_receipts: ' + (e.message.includes('exist') ? 'tabela nao existe' : e.message)); }

    // 4. Anonimizar v2_invoices (retencao fiscal 7 anos)
    try {
      await sequelize.query(
        \`UPDATE v2_invoices SET
          description = 'LGPD_DELETED',
          updated_at = NOW()
        WHERE user_id = :userId\`,
        { replacements: { userId } }
      );
      console.log('v2_invoices: anonimizado (retencao fiscal)');
    } catch(e) { console.log('v2_invoices: ' + (e.message.includes('exist') ? 'tabela nao existe' : e.message)); }

    // 5. V2Subscription
    try {
      await sequelize.query('DELETE FROM v2_subscriptions WHERE user_id = :userId', { replacements: { userId } });
      console.log('v2_subscriptions: deleted');
    } catch(e) { console.log('v2_subscriptions: ' + (e.message.includes('exist') ? 'tabela nao existe' : e.message)); }

    // 6. PagarmeCustomer
    try {
      await sequelize.query('DELETE FROM pagarme_customers WHERE user_id = :userId', { replacements: { userId } });
      console.log('pagarme_customers: deleted');
    } catch(e) { console.log('pagarme_customers: ' + (e.message.includes('exist') ? 'tabela nao existe' : e.message)); }

    // 7. StripeCustomer
    try {
      await sequelize.query('DELETE FROM stripe_customers WHERE user_id = :userId', { replacements: { userId } });
      console.log('stripe_customers: deleted');
    } catch(e) { console.log('stripe_customers: ' + (e.message.includes('exist') ? 'tabela nao existe' : e.message)); }

    // 8. Legacy: receipts, invoices, subscriptions
    for (const table of ['receipts', 'invoices', 'subscriptions']) {
      try {
        await sequelize.query('DELETE FROM ' + table + ' WHERE user_id = :userId', { replacements: { userId } });
        console.log(table + ' (legacy): deleted');
      } catch(e) { console.log(table + ' (legacy): ' + (e.message.includes('exist') ? 'tabela nao existe' : e.message)); }
    }

    console.log('BILLING_DONE');
  } catch(e) {
    console.error('BILLING_ERROR:' + e.message);
  } finally {
    await sequelize.close();
  }
}

deleteUserData();
"
```

Substituir `USER_ID_PLACEHOLDER` pelo `user_id` obtido na Fase 1.

- Se houver `BILLING_ERROR`: logar o erro mas **continuar** para a Fase 3 (o Web Backend deve ser limpo independentemente)
- Se o usuário não tiver registros no Billing (erro de "não encontrado"): logar ausência e continuar

---

## FASE 4 — Deletar Dados no Web Backend (Rails)

Execute via `kubectl exec` com psql direto no pod de produção (abordagem confiável — evita problemas com versão do Ruby local):

```bash
POD=$(kubectl get pods -l app=api -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- sh -c "PGPASSWORD=\$RDS_PASSWORD psql -h \$RDS_HOSTNAME -U \$RDS_USERNAME -d \$RDS_DB_NAME -c \"
BEGIN;

-- 1. Cadeia learning_plans → learning_blocks → content_items (netos primeiro)
DELETE FROM content_items
  WHERE learning_block_id IN (
    SELECT id FROM learning_blocks
    WHERE learning_plan_id IN (SELECT id FROM learning_plans WHERE user_id = USER_ID_PLACEHOLDER)
  );
DELETE FROM content_completions
  WHERE learning_plan_id IN (SELECT id FROM learning_plans WHERE user_id = USER_ID_PLACEHOLDER);
DELETE FROM learning_blocks
  WHERE learning_plan_id IN (SELECT id FROM learning_plans WHERE user_id = USER_ID_PLACEHOLDER);
DELETE FROM learning_plans WHERE user_id = USER_ID_PLACEHOLDER;

-- 2. Dependências diretas em users (ordem alfabética, todas seguras)
DELETE FROM ai_book_questions_histories    WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM app_receipts                   WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM bifocal_ratings                WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM book_leads                     WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM book_suggestions               WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM challenge_archievement_users   WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM challenges                     WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM content_completions            WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM daily_reminders                WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM experiment_users               WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM facebook_data_deletions        WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM failed_play_store_validations  WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM gift_books                     WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM gift_invites                   WHERE guest_id = USER_ID_PLACEHOLDER OR purchaser_id = USER_ID_PLACEHOLDER;
DELETE FROM highlights                     WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM invoices                       WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM invites_data                   WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM language_learning_progresses   WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM notification_tokens            WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM notifications                  WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM partner_vouchers               WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM payment_queues                 WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM pins                           WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM quiz_question_user_answers     WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM referral_rewards               WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM referrals                      WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM subscriptions                  WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM team_invoices                  WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM team_managers                  WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM team_users                     WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM user_anonymous_ids             WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM user_categories                WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM user_onboarding_answers        WHERE user_id = USER_ID_PLACEHOLDER;
DELETE FROM user_reading_goal_completions  WHERE user_id = USER_ID_PLACEHOLDER;

-- 3. Library + librarians
DELETE FROM librarians
  WHERE library_id IN (SELECT id FROM libraries WHERE user_id = USER_ID_PLACEHOLDER);
DELETE FROM libraries WHERE user_id = USER_ID_PLACEHOLDER;

-- 4. Deletar o usuário
DELETE FROM users WHERE id = USER_ID_PLACEHOLDER;

SELECT 'WEB_USER_DELETED:USER_ID_PLACEHOLDER' AS result;
COMMIT;
\""
```

Substituir `USER_ID_PLACEHOLDER` pelo `user_id` da Fase 1 (todas as ocorrências).

- `COMMIT` sem erros = sucesso
- Se retornar novo erro de FK: rodar a query de mapeamento abaixo e adicionar a tabela faltante antes do `DELETE FROM users`:

```bash
# Query para descobrir novas dependências FK caso surja erro
kubectl exec $POD -- sh -c "PGPASSWORD=\$RDS_PASSWORD psql -h \$RDS_HOSTNAME -U \$RDS_USERNAME -d \$RDS_DB_NAME -c \"
SELECT tc.table_name AS dependent_table, ccu.table_name AS referenced_table, kcu.column_name AS fk_column
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND ccu.table_name IN ('users','learning_plans','libraries','subscriptions')
ORDER BY referenced_table, dependent_table;
\""
```

---

## FASE 5 — Verificação e Confirmação Final

Após todas as fases, execute uma verificação via kubectl:

```bash
POD=$(kubectl get pods -l app=api -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- sh -c "PGPASSWORD=\$RDS_PASSWORD psql -h \$RDS_HOSTNAME -U \$RDS_USERNAME -d \$RDS_DB_NAME -c \"SELECT id FROM users WHERE email = 'EMAIL_PLACEHOLDER';\""
```

- `(0 rows)` → `VERIFICACAO_OK` — usuário deletado com sucesso
- Qualquer row retornada → `VERIFICACAO_FALHOU` — investigar manualmente

---

## FASE 6 — Registrar Audit Log no ClickUp

Após todas as fases, criar uma task na lista **"LGPD — Exclusões de Usuário"** (list_id: `901325600746`) usando a ferramenta `mcp__claude_ai_ClickUp__clickup_create_task`.

**Campos da task:**

- **name:** `[LGPD] Exclusão - <email> - <data no formato YYYY-MM-DD>`
- **status:** `complete`
- **description:** Preencher com o log completo da operação no formato abaixo:

```
## Solicitação de Exclusão LGPD

**Email:** <email>
**User ID:** <user_id>
**Data/Hora (UTC):** <timestamp>
**Executado por:** lgpd-delete-user (Claude Code)

---

## Sistemas Externos

| Sistema | Status | Detalhe |
|---------|--------|---------|
| ActiveCampaign | ✅ Deletado / ⚠️ Não encontrado / ❌ Erro | id=XXXXX |
| Amplitude | ⏳ Agendado (30 dias) / ❌ Erro | job_id=XXXXX |
| OneSignal | ✅ Deletado / ⚠️ Não encontrado / ❌ Erro | external_id=XXXXX |
| Adjust | ✅ X dispositivo(s) esquecido(s) / ⚠️ Não encontrado / ❌ Erro | adid=XXXXX |
| SendGrid | ✅ Suprimido / ❌ Erro | suppression global |
| RudderStack (BigQuery) | ✅ Deletado (~130 tabelas) / ❌ Erro | user_id + email |
| Twilio | ✅ X mensagem(ns) deletada(s) / ⚠️ Não encontrado / ⏭️ Sem telefone / ❌ Erro | phone=XXXXX |

## Billing Service

| Tabela | Status |
|--------|--------|
| adjust_headers | ✅ Deletado / N/A |
| tenjin_headers | ✅ Deletado / N/A |
| v2_receipts | 〜 Anonimizado (retenção fiscal 7 anos) |
| v2_invoices | 〜 Anonimizado (retenção fiscal 7 anos) |
| v2_subscriptions | ✅ Deletado / N/A |
| pagarme_customers | ✅ Deletado / N/A |
| stripe_customers | ✅ Deletado / N/A |
| subscriptions/invoices/receipts (legacy) | ✅ Deletado / N/A |

## Web Backend

| Associação | Registros |
|------------|-----------|
| pins | X deletados |
| library + librarians | X deletados |
| subscription | deletado |
| user_anonymous_id | deletado |
| ... | ... |
| Usuário | ✅ DELETADO |

## Verificação Pós-Deleção

`User.find_by(email:)` → nil ✅ Confirmado
```

- Usar os valores reais coletados durante a execução das fases anteriores
- Se algum sistema retornou erro, marcar claramente na tabela com ❌ e incluir o detalhe do erro

---

## Resumo Final

Exibir um resumo estruturado da operação:

```
════════════════════════════════════════════════════
  LGPD — EXCLUSÃO DE USUÁRIO CONCLUÍDA
════════════════════════════════════════════════════
Email:      <email>
User ID:    <user_id>
Timestamp:  <data e hora UTC>

SISTEMAS EXTERNOS:
  ✓ ActiveCampaign         — contato deletado (id=XXXXX)
  ~ Amplitude              — deleção AGENDADA (job_id=XXXXX, até 30 dias)
  ✓ OneSignal              — usuário deletado (external_id=XXXXX)
  ✓ Adjust                 — X dispositivo(s) esquecido(s) (adid=XXXXX)
  ✓ SendGrid               — email suprimido (suppression global)
  ✓ Twilio                 — X mensagem(ns) deletada(s) / ⚠️ sem telefone cadastrado

BILLING SERVICE:
  ✓ adjust_headers         — deletado
  ✓ tenjin_headers         — deletado
  ~ v2_receipts            — ANONIMIZADO (retenção fiscal 7 anos)
  ~ v2_invoices            — ANONIMIZADO (retenção fiscal 7 anos)
  ✓ v2_subscriptions       — deletado
  ✓ pagarme_customers      — deletado
  ✓ stripe_customers       — deletado
  ✓ receipts/invoices/subscriptions (legacy) — deletado

WEB BACKEND:
  ✓ highlights             — X deletados
  ✓ library + librarians   — X deletados
  ... (todos os registros)
  ✓ Usuário               — DELETADO

VERIFICAÇÃO: ✓ Usuário não encontrado no sistema

AUDIT LOG: ✓ Task criada no ClickUp
  → https://app.clickup.com/9013887712/v/l/li/901325600746

⚠️  AÇÃO MANUAL NECESSÁRIA nas plataformas externas (se necessário):
  • RudderStack  — Suppression via API se necessário
  • Mixpanel     — Deletar via GDPR API se necessário
════════════════════════════════════════════════════
```

---

## Tratamento de Erros

- **Containers não respondem:** Orientar o usuário a subir os containers com `cd /Users/renatofilho/Projects/web && docker compose up -d` e `cd /Users/renatofilho/Projects/billing && docker compose up -d`
- **ActiveCampaign não encontrado (`AC_NOT_FOUND`):** Logar e continuar — usuário pode nunca ter entrado no AC (ex: nunca confirmou email)
- **ActiveCampaign erro de API (`AC_ERROR`):** Logar HTTP code e body, continuar com demais fases. Anotar para verificação manual em https://12min.activehosted.com
- **Amplitude agendado (`AMPLITUDE_QUEUED`):** Normal — a Amplitude processa a deleção em até 30 dias. Guardar o `job_id` para auditoria
- **Amplitude erro (`AMPLITUDE_ERROR`):** Logar e continuar. A chave está no Secret `12min-credentials` como `AMPLITUDE_SECRET_KEY`. Verificar manualmente em https://analytics.amplitude.com → Settings → Privacy → Deletion Jobs
- **OneSignal não encontrado (`OS_NOT_FOUND`):** Logar e continuar — usuário nunca usou o app móvel ou tokens já expiraram
- **OneSignal erro de API (`OS_ERROR`):** Logar HTTP code e body, continuar com demais fases. Verificar manualmente em https://dashboard.onesignal.com
- **Usuário não existe no Billing:** Logar ausência e continuar (não é erro — usuário pode nunca ter tido assinatura)
- **Erro parcial no Web Backend:** Reportar qual associação falhou; o usuário pode precisar de intervenção manual via Rails console
- **Adjust não encontrado (`ADJUST_NOT_FOUND`):** Logar e continuar — usuário nunca usou o app móvel com tracking habilitado
- **Adjust erro de API (`ADJUST_ERROR`):** Logar HTTP code e body, continuar com demais fases. Verificar manualmente em https://dash.adjust.com → Data Privacy → Forget Device
- **SendGrid suprimido (`SG_SUPPRESSED`):** Sucesso — email bloqueado para futuros envios
- **SendGrid erro (`SG_ERROR`):** Logar HTTP code e body, continuar com demais fases. Verificar manualmente em https://app.sendgrid.com/suppressions/global_unsubscribes
- **Twilio sem telefone (`TWILIO_SKIPPED`):** Normal — usuário não tem `phone` cadastrado, pular a fase
- **Twilio não encontrado (`TWILIO_NOT_FOUND`):** Logar e continuar — usuário nunca recebeu SMS
- **Twilio erro (`TWILIO_ERROR`):** Logar SID e continuar. Verificar manualmente no Twilio Console → Monitor → Logs
- **BigQuery permissão negada no MCP (`Permission bigquery.tables.updateData denied`):** Normal — o MCP só tem leitura. Usar `bq` CLI via Bash para os DELETEs
- **`bq` CLI sem autenticação:** Rodar `gcloud auth login` ou verificar `gcloud auth list`
- **Usuário ainda existe após deleção:** Reportar como erro crítico e solicitar investigação manual
