# Guia de deploy AWS — seletiva SC2026

Este roteiro foi escrito para uma pessoa iniciante que tem **35 créditos no AWS Academy Learner Lab** e quer limitar este projeto a **no máximo 10 créditos**. O objetivo é aprender e testar os dois desafios sem deixar recursos ligados nem criar infraestrutura desnecessária.

> **Não existe garantia de que um conjunto de recursos custará exatamente 10 créditos.** Créditos do Learner Lab não são necessariamente dólares; preço, conversão, região permitida e atualização do saldo dependem da turma. Confira o saldo na tela do Learner Lab antes e depois de cada sessão. Billing/Cost Explorer pode atualizar com atraso. AWS Budgets pode alertar, mas não desliga os recursos e não impõe um teto rígido.

**Regra principal:** faça o máximo localmente, valide os componentes baratos da AWS em seguida e crie recursos cobrados por hora (RDS, EC2, ECS Fargate, ALB e IPv4 público) somente quando estiver pronto para um teste curto. Se o custo estimado ou o saldo estiver incerto, **não crie o próximo recurso cobrado por hora**. Não consuma os 25 créditos restantes em tentativas.

## 1. Estratégia de baixo custo: a ordem de trabalho

### Etapa 1 — Preparar e testar localmente

Sem criar infraestrutura AWS:

- leia o código e confirme as portas, variáveis e rotas;
- rode API e Frontend localmente e teste `/health`, catálogo, carrinho e pedido;
- compile o processador Go e teste o esquema PostgreSQL em um PostgreSQL local;
- construa as imagens Docker e verifique que iniciam;
- corrija os erros locais antes de iniciar qualquer serviço cobrado por hora.

Isso evita pagar por RDS ou Fargate enquanto se corrige código, imagem ou configuração.

### Etapa 2 — Usar primeiro serviços cobrados por uso

No Dia 1, teste poucas requisições com **DynamoDB, Lambda e API Gateway HTTP API**. No Dia 2, crie as tabelas DynamoDB, faça o seed e publique as imagens no ECR. Esses serviços ainda podem gerar custo, mas não deixam um servidor de banco ou container rodando continuamente.

### Etapa 3 — Testar a integração completa por último

- **Dia 1:** só depois do teste da API, crie RDS e uma EC2 pequena para o processador Go. Valide um ou dois registros e encerre ambos. O RDS pode levar alguns minutos para provisionar, e esse tempo também conta.
- **Dia 2:** só depois do teste local e do push ao ECR, crie um ALB e duas tarefas Fargate (API e Frontend), cada uma com desired count `1`. Teste uma compra e apague os serviços e o ALB.
- Faça um dia por sessão. Não deixe recursos do Dia 1 ligados enquanto pratica o Dia 2.

### Recursos a evitar no estudo econômico

Não crie NAT Gateway, VPC nova, Auto Scaling, Multi-AZ, réplicas, instâncias extras, domínio, certificado pago ou grande carga de teste. Reutilize a VPC, as sub-redes e os papéis fornecidos pelo laboratório. Esses componentes aumentam custo e trabalho e não são necessários para aprender o caminho básico.

Não rode o Locust nem envie muitas requisições durante o estudo inicial: carga gera mais chamadas e pode elevar custos. Primeiro prove uma chamada ponta a ponta. O teste de concorrência do desafio deve ser feito quando solicitado e com o saldo/custos conferidos.

### Decisão antes de cada recurso por hora

Antes de apertar **Create** para RDS, EC2, ECS/Fargate ou ALB:

1. confira o saldo atual do Learner Lab;
2. consulte o AWS Pricing Calculator para a região e duração estimada, se disponível;
3. confira se o serviço e o tamanho são permitidos no Learner Lab;
4. confirme que o restante do fluxo já está testado localmente;
5. anote o horário de início e quais recursos está criando;
6. tenha aberto o console/página de exclusão para conseguir encerrar logo após o teste.

Não converta os créditos em um valor em dólares por conta própria. O preço divulgado pela AWS é uma estimativa de cobrança, enquanto o Learner Lab aplica as próprias regras de crédito.

## 2. Arquiteturas que serão testadas

### Dia 1 — reclamações

```text
Cliente
  → API Gateway HTTP API
  → Lambda (valida e grava)
  → DynamoDB complaints (processed=false)
  → processador Go em EC2 temporária
  → RDS PostgreSQL temporário (TLS)
  → processador marca processed=true no DynamoDB
```

**O que testar primeiro sem RDS/EC2:** API Gateway → Lambda → DynamoDB. Para repetir o processamento, use PostgreSQL local e teste o código Go localmente. **O teste final do desafio** usa RDS e EC2 por um período curto para provar a conexão AWS real.

### Dia 2 — loja

```text
Navegador → ALB → ECS Fargate Frontend (Flask)
                       → ECS Fargate API (FastAPI)
                       → DynamoDB (products, cart, orders)
```

As imagens ficam no ECR. O ALB e as duas tarefas Fargate só são criados quando todo o restante já foi testado. Uma tarefa por serviço é suficiente para comprovar o fluxo de estudo; não é uma configuração de alta disponibilidade.

## 3. Preparar o terminal Linux

Use Bash em Ubuntu, Amazon Linux, WSL ou ambiente Linux equivalente. Os comandos não são comandos PowerShell. No CloudShell, AWS CLI pode estar pronta, mas Docker e acesso a uma VPC privada podem não estar.

Confirme as ferramentas antes da sessão:

```bash
aws --version
docker --version
go version
python3 --version
curl --version
jq --version
```

Instale dependências antes do dia da prova, não durante o deploy cronometrado. Em Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y unzip curl jq python3 python3-venv python3-pip golang-go
```

Instale o Docker Engine seguindo a documentação da distribuição e confirme que ele está iniciado. Não compartilhe credenciais AWS e não grave access keys em código, imagem Docker, shell script ou Git.

Configure somente a região indicada pelo laboratório:

```bash
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="$AWS_REGION"
aws sts get-caller-identity
aws configure list
```

Não defina `AWS_PROFILE=default` sem saber como o Learner Lab fornece credenciais: isso pode substituir ou ignorar credenciais temporárias do ambiente. Se `aws sts get-caller-identity` falhar, pare e resolva a sessão antes de criar recursos.

Anote a região e a conta da atividade:

```bash
export REGION="$AWS_REGION"
export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
printf 'Conta: %s | Região: %s\n' "$ACCOUNT_ID" "$REGION"
```

## 4. Dia 1 — começar pelo teste barato

### 4.1 Para que serve cada serviço

| Serviço | Função no desafio | Por que essa escolha reduz trabalho |
|---|---|---|
| API Gateway HTTP API | Recebe `POST /complaints` por HTTPS. | Endpoint gerenciado e mais simples para este caso que criar um servidor web próprio. |
| Lambda | Valida JSON, gera o ID e grava no DynamoDB. | Executa sob demanda; não precisa deixar uma máquina ligada. |
| DynamoDB | Guarda reclamações pendentes. | Serviço gerenciado; `PAY_PER_REQUEST` não exige dimensionar capacidade para um teste pequeno. |
| EC2 | Executa o binário Go que consulta DynamoDB. | Maneira direta de rodar o processador contínuo fornecido no repositório. Será temporária no estudo. |
| RDS PostgreSQL | Guarda reclamações enriquecidas. | Cumpre o requisito relacional do desafio; custa por tempo provisionado, então será criado só no teste final. |
| CloudWatch Logs | Guarda logs da Lambda e do processador. | Permite comprovar execução e diagnosticar falhas. |

O repositório não contém código da Lambda; contém o processador Go em `day1/assets/processor.go`, o esquema em `day1/test/init-db.sql` e o teste de carga em `day1/test/locustfile.py`.

### 4.2 Criar DynamoDB (baixo volume)

A rubrica automatizada espera partition key `complaint_id` e sort key `customer_id`. Crie a tabela uma única vez:

```bash
aws dynamodb create-table \
  --table-name complaints \
  --attribute-definitions \
    AttributeName=complaint_id,AttributeType=S \
    AttributeName=customer_id,AttributeType=S \
  --key-schema \
    AttributeName=complaint_id,KeyType=HASH \
    AttributeName=customer_id,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

aws dynamodb wait table-exists --table-name complaints --region "$REGION"
aws dynamodb describe-table --table-name complaints --region "$REGION" \
  --query 'Table.{Status:TableStatus,Keys:KeySchema,Billing:BillingModeSummary.BillingMode}'
```

Se receber `ResourceInUseException`, não tente criar outra tabela: confira a existente com `describe-table`. `PAY_PER_REQUEST` é adequado a poucos testes e evita reservar throughput; não significa custo zero.

### 4.3 Criar e publicar a Lambda

Crie uma pasta de trabalho para a Lambda:

```bash
mkdir -p ~/sc2026-lambda
cd ~/sc2026-lambda
```

Crie `lambda_function.py` com este conteúdo. Ele valida o JSON e grava os nomes de atributos esperados pelo processador:

```python
import json
import os
import uuid
from datetime import datetime, timezone

import boto3

table = boto3.resource(
    "dynamodb",
    region_name=os.environ.get("AWS_REGION", "us-east-1"),
).Table(os.environ.get("COMPLAINTS_TABLE", "complaints"))


def respond(status, data):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(data),
    }


def handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except (TypeError, json.JSONDecodeError):
        return respond(400, {"error": "body must be valid JSON"})

    customer_id = body.get("customer_id")
    message = body.get("message")
    severity = body.get("severity")
    if not all(isinstance(value, str) and value.strip()
               for value in (customer_id, message, severity)):
        return respond(400, {
            "error": "customer_id, message and severity are required"
        })
    if severity.lower() not in {"low", "medium", "high"}:
        return respond(400, {"error": "severity must be low, medium or high"})

    complaint_id = "comp_" + uuid.uuid4().hex
    table.put_item(Item={
        "complaint_id": complaint_id,
        "customer_id": customer_id.strip(),
        "message": message.strip(),
        "severity": severity.lower(),
        "created_at": int(datetime.now(timezone.utc).timestamp()),
        "processed": False,
    })
    return respond(200, {
        "complaint_id": complaint_id,
        "status": "received",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })
```

Empacote:

```bash
zip -j lambda.zip lambda_function.py
```

No console AWS, navegue até **Lambda → Create function → Author from scratch**:

1. Nome `complaint-intake`; escolha um runtime Python disponível no laboratório.
2. Use o papel permitido pelo Learner Lab (o enunciado cita `LabRole`). Esse papel precisa gravar na tabela `complaints` e escrever logs. Não crie permissões amplas se o laboratório já fornece o papel.
3. Faça upload de `lambda.zip`; configure o handler como `lambda_function.handler`.
4. Em **Configuration → Environment variables**, adicione `AWS_REGION` com a região e `COMPLAINTS_TABLE=complaints`.
5. Use memória e timeout modestos. Logs do CloudWatch devem permanecer habilitados.

**Por que não usamos uma EC2 para a API?** Lambda e API Gateway eliminam uma máquina ligada continuamente e cobrem exatamente a entrada do Dia 1.

### 4.4 Criar API Gateway e testar

No console, crie uma **HTTP API** no API Gateway:

1. Adicione a Lambda `complaint-intake` como integração.
2. Crie a rota `POST /complaints`.
3. Permita que o API Gateway invoque a Lambda (o wizard do console pode criar essa permissão).
4. Faça deploy em `$default` ou `prod` e copie a Invoke URL.

Teste uma mensagem válida:

```bash
export API_URL="https://ID.execute-api.REGION.amazonaws.com"
curl -i -X POST "$API_URL/complaints" \
  -H 'content-type: application/json' \
  -d '{"customer_id":"cust_demo","message":"Pagamento falhou e preciso de ajuda","severity":"high"}'
```

Esperado: HTTP 200, `complaint_id` e status `received`. Teste JSON inválido também; deve retornar 400:

```bash
curl -i -X POST "$API_URL/complaints" \
  -H 'content-type: application/json' -d '{"customer_id":"x"}'
```

Confirme que chegou ao DynamoDB:

```bash
aws dynamodb scan --table-name complaints --region "$REGION" \
  --filter-expression 'customer_id = :c' \
  --expression-attribute-values '{":c":{"S":"cust_demo"}}' \
  --query 'Items[].{id:complaint_id.S,message:message.S,processed:processed.BOOL}'
```

Nesse ponto, o teste serverless está feito. **Não crie RDS/EC2 ainda** se a lógica do endpoint falhar.

### 4.5 Testar o processador sem RDS AWS

Antes de pagar por banco gerenciado:

1. Compile o programa Go para confirmar dependências e arquitetura.
2. Use PostgreSQL local para praticar SQL e conferir a tabela definida em `day1/test/init-db.sql`.
3. Confira a lógica de enriquecimento no processador: pontuação entre 1 e 10, categoria e gravação idempotente.
4. Só depois de entender esse fluxo considere o teste final em RDS.

Comandos de compilação em Linux, a partir da raiz do repositório:

```bash
cd day1/assets
go mod download
GOOS=linux GOARCH=amd64 go build -o /tmp/sc2026-processor .
file /tmp/sc2026-processor
```

Se a instância EC2 for ARM/Graviton, use `GOARCH=arm64` e confirme `uname -m` nela antes de copiar o binário. Compilar localmente antes economiza tempo de instância.

Para praticar somente a criação do esquema PostgreSQL sem RDS, suba um banco local temporário com Docker:

```bash
docker run --name sc2026-postgres \
  -e POSTGRES_USER=admin \
  -e POSTGRES_PASSWORD=dev-only \
  -e POSTGRES_DB=complaints_db \
  -p 5432:5432 -d postgres:16
```

Na raiz do repositório, aplique o SQL do projeto e consulte uma tabela:

```bash
docker exec -i sc2026-postgres \
  psql -U admin -d complaints_db < day1/test/init-db.sql
docker exec -it sc2026-postgres \
  psql -U admin -d complaints_db \
  -c '\dt' \
  -c 'SELECT COUNT(*) FROM processed_complaints;'
```

`dev-only` é apenas para este banco local isolado; nunca reutilize essa senha no RDS. Ao terminar a prática local:

```bash
docker rm -f sc2026-postgres
```

Isso não cria nem remove recursos AWS e não consome créditos do Learner Lab.

### 4.6 Teste final do Dia 1 com RDS e EC2 (temporário)

Esta etapa comprova a arquitetura completa, mas é a parte que tem mais risco de consumir créditos. Faça-a somente depois dos testes anteriores e se o saldo e a estimativa permitirem. **Não crie NAT Gateway nem VPC nova.**

No console **RDS → Create database**:

1. Engine PostgreSQL, template de desenvolvimento/teste e a menor classe permitida pelo laboratório.
2. No nome inicial do banco, use `complaints_db` (o processador lê `RDS_DB`); Single-AZ, sem réplica, com armazenamento mínimo permitido.
3. Desative **Public access**. Use a VPC do laboratório.
4. Use/crie SG para aceitar TCP 5432 **somente do SG da EC2 processadora**.
5. Use credenciais de laboratório; não escreva senha no repositório. Ative SSL conforme o parâmetro permitido (`rds.force_ssl=1`) e a rubrica.
6. Aguarde `Available` e copie somente o endpoint DNS do RDS.

Crie uma EC2 pequena autorizada na mesma VPC e em sub-rede com conectividade de saída já disponível. Associe o papel fornecido que permite acesso ao DynamoDB. No SG da EC2, limite SSH ao seu IP; **nunca** abra SSH para qualquer origem. O RDS permanece privado e só aceita o SG desta EC2.

O processador Go precisa conversar com RDS na VPC e com DynamoDB. Se a VPC do laboratório não tiver a rota de saída necessária, não tente corrigir criando NAT Gateway; interrompa e peça orientação ao instrutor.

Copie o binário se houver SSH permitido:

```bash
scp -i "$SSH_KEY" /tmp/sc2026-processor \
  ec2-user@"$PROCESSOR_HOST":/home/ec2-user/processor
```

Na EC2:

```bash
chmod 700 /home/ec2-user/processor
export AWS_REGION="us-east-1"
export COMPLAINTS_TABLE="complaints"
export RDS_HOST="SEU-ENDPOINT.rds.amazonaws.com"
export RDS_PORT="5432"
export RDS_USER="SEU_USUARIO"
export RDS_DB="complaints_db"
read -r -s -p "Senha do RDS: " RDS_PASSWORD; echo
export RDS_PASSWORD
./processor
```

O processador varre DynamoDB a cada cinco segundos, grava no PostgreSQL usando `sslmode=require` e só então define `processed=true`. Observe os logs. Valide um registro; não use carga massiva nessa etapa de orçamento.

Se `psql` estiver disponível, confirme:

```sql
SELECT complaint_id, customer_id, severity_score, ai_category, processed_at
FROM processed_complaints
ORDER BY processed_at DESC
LIMIT 5;
```

Guarde evidência (ID, status e horário), pare o processador, encerre a EC2 e exclua RDS quando não precisar mais dos dados. RDS continua cobrando enquanto provisionado; snapshot final também ocupa armazenamento. Só pule o snapshot se os dados forem realmente descartáveis.

## 5. Dia 2 — começar local e só então usar AWS

### 5.1 Função dos serviços

| Serviço | Responsabilidade | Motivo |
|---|---|---|
| DynamoDB | Guarda `products`, `cart` e `orders`. | Sem servidor de banco para administrar; on-demand é prático para volume de treino. |
| Docker | Empacota API e Frontend. | A mesma imagem pode ser testada localmente e executada no ECS. |
| ECR | Armazena as imagens privadas. | ECS baixa imagens do registro AWS da mesma região. |
| ECS/Fargate | Executa API e Frontend em containers sem gerenciar hosts. | Cumpre a exigência de containers com menos manutenção que ECS sobre EC2. |
| ECS Service | Mantém a quantidade desejada de tasks. | Permite iniciar, observar e atualizar os containers. |
| ALB | Recebe tráfego e envia ao container certo; checa saúde. | Dá endpoints para testar o Frontend e a API. |
| CloudWatch Logs | Guarda saída dos containers. | Ajuda a encontrar falha sem entrar na task. |

No ECS, **execution role** é usada pelo agente para pull no ECR e envio de logs; **task role** é usada pelo código Python para acessar DynamoDB. Não coloque access key na imagem.

### 5.2 Testar as aplicações localmente

Primeiro teste a API em Python, com credenciais válidas do laboratório se for acessar DynamoDB real. Em um terminal:

```bash
cd day2/api
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
export AWS_REGION="us-east-1"
uvicorn main:app --host 0.0.0.0 --port 8000
```

Em outro terminal:

```bash
curl -i http://localhost:8000/health
curl -s http://localhost:8000/products | jq .
curl -i -X POST http://localhost:8000/cart/cart_demo \
  -H 'content-type: application/json' \
  -d '{"product_id":"prod_001","quantity":1}'
curl -s http://localhost:8000/cart/cart_demo | jq .
curl -i -X POST http://localhost:8000/orders \
  -H 'content-type: application/json' \
  -d '{"customer_id":"cust_demo","items":[{"product_id":"prod_001","quantity":1}]}'
```

Para o Frontend, em outro terminal:

```bash
cd day2/frontend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
export API_URL="http://localhost:8000"
export SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
python app.py
```

Teste `http://localhost:5000/health` e no navegador percorra catálogo → carrinho → checkout. `localhost` só serve para aplicações no mesmo computador; dentro de containers ou ECS, `localhost` aponta para o próprio container.

O código do Frontend pede `product.html`, ausente na lista de templates do repositório. Se essa página for obrigatória, corrija/teste-a antes de subir imagens. A API também encapsula algumas exceções de forma ampla; confira os logs quando uma rota devolver 500.

### 5.3 Criar as tabelas e inserir poucos produtos

Crie `products`, `orders` e `cart` com os esquemas exigidos. Execute apenas uma vez:

```bash
aws dynamodb create-table \
  --table-name products \
  --attribute-definitions AttributeName=product_id,AttributeType=S \
  --key-schema AttributeName=product_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region "$REGION"

aws dynamodb create-table \
  --table-name orders \
  --attribute-definitions AttributeName=order_id,AttributeType=S AttributeName=customer_id,AttributeType=S \
  --key-schema AttributeName=order_id,KeyType=HASH AttributeName=customer_id,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST --region "$REGION"

aws dynamodb create-table \
  --table-name cart \
  --attribute-definitions AttributeName=cart_id,AttributeType=S AttributeName=product_id,AttributeType=S \
  --key-schema AttributeName=cart_id,KeyType=HASH AttributeName=product_id,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST --region "$REGION"

aws dynamodb wait table-exists --table-name products --region "$REGION"
aws dynamodb wait table-exists --table-name orders --region "$REGION"
aws dynamodb wait table-exists --table-name cart --region "$REGION"
```

Se uma tabela já existir, não repita a criação; use `describe-table`. `PAY_PER_REQUEST` elimina a escolha de capacidade provisionada para esse pequeno teste, mas não torna as operações gratuitas.

Insira os produtos pelo script incluído:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install boto3
export AWS_REGION="$REGION"
python day2/assets/seed-dynamodb.py
aws dynamodb scan --table-name products --region "$REGION" --select COUNT
```

O seed tem 20 produtos e usa IDs fixos; executá-lo de novo atualiza os mesmos IDs. Para prova, ter cinco ou mais produtos basta segundo o enunciado/scorer.

### 5.4 Construir as imagens antes de provisionar ECS

Na raiz do repositório:

```bash
export TAG="study-$(date +%Y%m%d-%H%M)"
docker build -t ecommerce-api:"$TAG" ./day2/api
docker build -t ecommerce-frontend:"$TAG" ./day2/frontend
docker image ls | grep ecommerce
```

Confira que os containers iniciam e que `/health` funciona localmente. Não inclua credenciais AWS na imagem; em ECS, use task role. Use tag versionada, não somente `latest`, para saber que versão está sendo executada e facilitar retorno.

### 5.5 Publicar no ECR (depois dos testes locais)

ECR cobra armazenamento das imagens; mantenha somente as imagens de estudo necessárias. Crie os repositórios:

```bash
aws ecr create-repository --repository-name ecommerce-api --region "$REGION"
aws ecr create-repository --repository-name ecommerce-frontend --region "$REGION"
```

Se receber erro de repositório existente, não crie outro nome: consulte-o com `describe-repositories`. Login e push:

```bash
export ECR_REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

docker tag ecommerce-api:"$TAG" "$ECR_REGISTRY/ecommerce-api:$TAG"
docker tag ecommerce-frontend:"$TAG" "$ECR_REGISTRY/ecommerce-frontend:$TAG"
docker push "$ECR_REGISTRY/ecommerce-api:$TAG"
docker push "$ECR_REGISTRY/ecommerce-frontend:$TAG"
```

Nesse momento, as imagens estão publicadas, mas ainda não há tasks/ALB cobrados por hora. Confira que os pushes terminaram antes de avançar.

### 5.6 Deploy temporário ECS/Fargate + ALB

Esta é a etapa mais cara do Dia 2. Só inicie quando imagens e dados estiverem prontos, saldo conferido e você puder acompanhar o teste até a limpeza. O objetivo é uma implantação breve, não deixar um site no ar por dias.

#### Por que usar um ALB e duas tasks

- **ALB** aceita conexões e encaminha para grupos-alvo saudáveis.
- **Target group** aponta para uma porta/container. O tipo deve ser `IP` para Fargate com `awsvpc`.
- **Task definition** descreve imagem, CPU/memória, portas, roles, variáveis e logs.
- **ECS service** mantém uma task desejada para cada aplicação.
- **Fargate** evita criar e administrar um cluster de máquinas EC2 para os containers.

Para que o Frontend possa chamar a API sem criar NAT Gateway, a configuração de estudo descrita abaixo usa sub-redes públicas existentes e public IP nas tasks. **Isto é um compromisso didático, não uma arquitetura de produção.** As portas das tasks continuam aceitando entrada apenas do SG do ALB. O listener de API HTTP 8000 precisa ser acessível durante o teste; a API de exemplo não tem autenticação, então não deixe esse listener aberto depois de validar.

Se o laboratório não tiver VPC/sub-redes adequadas, ou a configuração exigir NAT Gateway, pare e pergunte ao instrutor. Não crie NAT Gateway para tentar manter esta arquitetura dentro do limite.

#### Criar pelo console (mais simples para iniciante)

1. **ECR:** confirme que os dois repositórios e as tags estão presentes.
2. **ALB:** crie um ALB internet-facing usando a VPC do Learner Lab e pelo menos duas sub-redes públicas existentes. Não crie VPC/sub-rede/NAT novos.
3. **Security group do ALB:** listener 80 para Frontend. Para o teste separado da API, listener 8000. Se o Frontend chamar `http://DNS_DO_ALB:8000`, a chamada também precisa chegar ao listener; deixe-o acessível somente pelo período do teste e remova o listener/ALB ao terminar. Não use esta configuração para dados reais.
4. **Target groups:** crie `ecommerce-frontend-tg` para tipo `IP`, HTTP porta 5000, health path `/health`; crie `ecommerce-api-tg` tipo `IP`, HTTP porta 8000, health path `/health`.
5. **Listeners:** listener 80 encaminha para o target group Frontend; listener 8000 para o target group API. Anote o DNS do ALB.
6. **Security group das tasks:** permita TCP 5000 e 8000 somente com origem no SG do ALB. Não abra essas portas diretamente para a Internet. Use o papel fornecido pela conta para execução de tasks e acesso DynamoDB.
7. **Cluster:** crie `ecommerce-cluster`.
8. **Task definition da API:** Fargate, `awsvpc`, Linux/x86_64 conforme a imagem, CPU 256 e memória 512 MiB como início. Container `api`, imagem versionada do ECR, porta 8000. Defina `AWS_REGION`, `PRODUCTS_TABLE=products`, `ORDERS_TABLE=orders`, `CART_TABLE=cart`.
9. **Task definition do Frontend:** Fargate, `awsvpc`, CPU 256/memória 512 MiB. Container `frontend`, imagem versionada, porta 5000, `API_URL=http://DNS_DO_ALB:8000`. Configure `SECRET_KEY` como segredo/valor temporário não versionado.
10. **Roles:** `executionRoleArn` permite ao ECS puxar ECR e criar logs; `taskRoleArn` dá à aplicação permissão para as operações necessárias nas tabelas. Use `LabRole` apenas como instruído; não coloque access keys nas variáveis do container.
11. **Logs e saúde:** configure `awslogs` para `/ecs/ecommerce-api` e `/ecs/ecommerce-frontend`. Use health check `/health` com comando presente na imagem. O exemplo de task definition do README cita `curl`, mas a imagem pode não tê-lo instalado; valide o comando.
12. **Services:** crie `ecommerce-api` e `ecommerce-frontend`, cada um com desired count `1`, public IP habilitado se a rede do laboratório exigir, SG das tasks e seu target group.
13. Aguarde as duas tasks em execução e targets `healthy`. Não aumente a contagem nem ligue Auto Scaling para este teste econômico.

O ALB é criado antes das tasks para obter seu DNS, necessário a `API_URL`. Por isso, anote o horário e mantenha esta parte curta: estabilidade → health checks → uma compra → limpeza.

#### Validar a loja e persistência

```bash
export ALB_DNS="SEU-ALB.REGION.elb.amazonaws.com"
export FRONTEND_URL="http://$ALB_DNS"
export API_URL="http://$ALB_DNS:8000"

curl -i "$FRONTEND_URL/health"
curl -i "$API_URL/health"
curl -s "$API_URL/products" | jq .
curl -s "$API_URL/products" | jq '.products | length'
```

O endpoint do código retorna um objeto `{ "products": [...], "count": n }`; conte com `.products | length`, não com o comprimento do objeto inteiro.

Teste carrinho e pedido:

```bash
curl -i -X POST "$API_URL/cart/cart_demo" \
  -H 'content-type: application/json' \
  -d '{"product_id":"prod_001","quantity":1}'
curl -s "$API_URL/cart/cart_demo" | jq .

curl -i -X POST "$API_URL/orders" \
  -H 'content-type: application/json' \
  -d '{"customer_id":"cust_demo","items":[{"product_id":"prod_001","quantity":1}]}'

aws dynamodb scan --table-name orders --region "$REGION" \
  --filter-expression 'customer_id = :c' \
  --expression-attribute-values '{":c":{"S":"cust_demo"}}'
```

Faça o fluxo visual no navegador também: abrir loja → adicionar ao carrinho → conferir carrinho → checkout → ver confirmação. Uma resposta HTTP 200 de `/health` não prova que compra ou persistência funcionam.

## 6. Manutenção e diagnóstico sem desperdiçar tentativas

### Primeiro: qual camada falhou?

Siga sempre **sintoma → evidência → uma correção → reteste**. Não crie recursos adicionais por tentativa aleatória.

| Sintoma | Primeiro lugar para olhar | Próximo passo |
|---|---|---|
| API Gateway retorna 5xx | Logs da Lambda e integração/rota do API Gateway. | Confira `message`, JSON, nome de tabela e permissão do papel. |
| DynamoDB AccessDenied | Papel Lambda/task e região configurada. | Corrija role/table/region; não use access key estática no código. |
| Processador não alcança RDS | Status do RDS, VPC, rotas e SG de origem/destino. | Porta 5432 só entre SGs corretos; não tornar RDS público. |
| ECS não inicia | ECS service events, stopped reason, CloudWatch Logs. | Confira imagem/tag, role de execução, rede e arquitetura da imagem. |
| ALB target unhealthy | Porta, health path, protocolo e SG. | Container tem que ouvir `0.0.0.0` e responder `/health`. |
| Frontend não chama API | Valor de `API_URL`, DNS do ALB e listener 8000. | Lembre que `localhost` em um container não é outro serviço. |
| Loja mostra poucos/nenhum produto | Resposta real de `/products`, seed e DynamoDB. | Verifique `.products` no JSON e tabela/região configurada. |

### Comandos de observação

```bash
aws sts get-caller-identity
aws dynamodb list-tables --region "$REGION"
aws ecs describe-clusters --clusters ecommerce-cluster --region "$REGION"
aws ecs list-services --cluster ecommerce-cluster --region "$REGION"
aws logs describe-log-groups --region "$REGION" \
  --query 'logGroups[].logGroupName'
```

Para acompanhar logs:

```bash
aws logs tail "/aws/lambda/complaint-intake" --since 15m --follow --region "$REGION"
aws logs tail "/ecs/ecommerce-api" --since 15m --follow --region "$REGION"
aws logs tail "/ecs/ecommerce-frontend" --since 15m --follow --region "$REGION"
```

O `--follow` mantém o comando aberto; pare com `Ctrl+C` quando terminar. Ver logs ajuda a corrigir a configuração sem repetir deploys.

## 7. Encerrar tudo após cada teste AWS

Não basta fechar o navegador ou encerrar o terminal: recursos AWS continuam executando na conta.

### Dia 2

1. No ECS, exclua os services ou reduza desired count para zero se for continuar em breve; confirme que não há tasks `RUNNING`.
2. Exclua o ALB temporário e seus target groups/listeners. O ALB pode cobrar mesmo sem requisições.
3. Se o estudo terminou, remova imagens ECR e log groups de teste que não precisar manter.
4. As tabelas DynamoDB on-demand podem ser mantidas para uma sessão próxima, mas remova-as quando não forem mais necessárias.

### Dia 1

1. Pare o processador e encerre/termine a EC2 temporária.
2. Exclua o RDS de treino quando tiver guardado os resultados. Não retenha snapshot se os dados forem descartáveis; essa decisão apaga os dados.
3. Se não for continuar o teste serverless, remova a Lambda, API Gateway e tabela de treino.

No Learner Lab, não remova recursos compartilhados ou preparados pelo instrutor. Confirme no console que serviços cobrados por hora foram encerrados. O painel pode atualizar com atraso; volte a conferir o saldo.

**Fontes comuns de consumo enquanto “não estou usando”:** RDS ativo, instância EC2 ligada, tasks ECS, ALB, NAT Gateway, endereços IPv4 públicos e snapshots. A regra do projeto é não ultrapassar 10 créditos; se o consumo não estiver claro, não crie mais recursos.

## 8. O que muda na seletiva real

Este guia minimiza custos de estudo, mas a avaliação pode exigir que tudo esteja ativo ao mesmo tempo e que o teste de carga seja executado. Na seletiva:

- siga instruções do avaliador e permissões do laboratório, mesmo que a arquitetura econômica de estudo tenha simplificado a topologia;
- confirme saldo e duração permitida antes de iniciar os componentes cobrados por hora;
- primeiro deixe o fluxo funcional; depois execute carga/otimizações se o tempo e o saldo permitirem;
- demonstre logs, saúde dos serviços e persistência final;
- ao final, remova apenas recursos criados por você se o regulamento permitir.

O scorer e os exemplos do repositório têm divergências que podem afetar a validação:

1. O código Lambda não está no repositório; o exemplo deste guia usa o campo `message`, igual ao processador Go. O scorer envia `complaint`. Confirme o contrato oficial antes de adaptar.
2. O scorer do Dia 1 espera a chave composta DynamoDB `complaint_id` + `customer_id`; use esse esquema.
3. O endpoint `/products` retorna objeto com campo `products`; o scorer parece contar a resposta inteira como lista. Demonstre a resposta real e use `jq '.products | length'`.
4. O Frontend cita `product.html`, mas esse template não aparece na lista de arquivos fornecida. Teste a página de detalhes se for critério.
5. Os exemplos de health check usam `curl`, que pode não existir na imagem. Verifique o comando contra a imagem construída.
6. O processador usa `sslmode=require`; a conexão exige TLS, mas o código não aplica a configuração de certificado declarada. Isso é relevante para produção; no desafio, cumpra a exigência explícita de TLS e explique a diferença.
7. Alguns itens da pontuação são manuais ou sempre reportados como falha pelo script; leia a rubrica e não conclua que a solução falhou somente por uma linha automatizada.

## 9. Checklist final de custo e funcionamento

### Antes de iniciar

- [ ] Conferi o saldo atual do Learner Lab e sei quais recursos vou criar.
- [ ] Fiz testes locais antes de iniciar RDS/EC2/Fargate/ALB.
- [ ] Reutilizarei VPC, sub-redes e roles do laboratório.
- [ ] Não criarei NAT Gateway, Multi-AZ, réplica ou Auto Scaling para o estudo.
- [ ] Tenho tempo para validar e apagar os recursos na mesma sessão.

### Dia 1 — provar o fluxo

- [ ] `POST /complaints` valida JSON e responde com `complaint_id`.
- [ ] DynamoDB guarda `processed=false`.
- [ ] Lambda e API Gateway têm logs/rota implantada.
- [ ] Para o teste completo: processador grava no PostgreSQL por TLS e depois define `processed=true`.
- [ ] EC2 e RDS foram encerrados após a validação.

### Dia 2 — provar o fluxo

- [ ] API e Frontend passam no teste local e têm `/health`.
- [ ] DynamoDB contém ao menos cinco produtos de teste.
- [ ] Imagens versionadas foram publicadas no ECR.
- [ ] ECS mantém uma task por serviço e ALB tem targets saudáveis.
- [ ] Catálogo, carrinho e criação do pedido foram verificados; pedido aparece no DynamoDB.
- [ ] Tasks ECS e ALB foram removidos ao fim do teste.

### Depois de cada sessão

- [ ] Verifiquei novamente o saldo e os recursos ativos no console do Learner Lab.
- [ ] Anotei o que funcionou e o erro que devo resolver antes da próxima sessão.
- [ ] Não deixei RDS, EC2, ECS, ALB ou NAT Gateway ativos.

Se algum item de custo estiver incerto, a ação correta é pausar o deploy e confirmar no Learner Lab/instrutor — não continuar criando recursos às cegas.
