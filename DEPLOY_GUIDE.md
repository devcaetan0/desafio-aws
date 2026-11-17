# Guia de preparação — Seletiva SC2026 (AWS)

Este guia transforma os materiais de `day1/`, `day2/` e `assessment/` em um roteiro de execução e manutenção. A perspectiva é de avaliação: não basta criar recursos AWS; é preciso demonstrar um fluxo funcional, seguro, observável e coerente com o tempo e o orçamento da prova.

> **Prioridade na competição:** siga o enunciado e a rubrica oficial disponibilizada pelo avaliador. Os arquivos do repositório têm divergências e alguns verificadores automáticos têm limitações (detalhadas em [Pontos de atenção](#pontos-de-atenção-nos-materiais)). Não gaste tempo tentando “agradar ao script” à custa de quebrar o requisito real.

## 1. O que a seletiva está avaliando

Os dois desafios usam situações diferentes, mas medem habilidades semelhantes:

1. **Fazer a solução funcionar de ponta a ponta.** Teste pela entrada pública prevista e confirme que os dados chegam ao destino final.
2. **Implantar corretamente na AWS.** Região, IAM, rede, imagens, serviços, verificações de saúde e integração entre recursos precisam estar certos.
3. **Operar e diagnosticar.** Use logs e eventos para identificar falhas; não dependa de “parece estar funcionando”.
4. **Proteger dados e credenciais.** Use papéis IAM, grupos de segurança restritivos, TLS e armazenamento apropriado para segredos.
5. **Atender desempenho, confiabilidade e custo.** Teste carga e latência, evite recursos superdimensionados e elimine recursos temporários ao final.

O `MARKING_GUIDE.md` organiza a avaliação pelos cinco pilares Well-Architected: Excelência Operacional, Segurança, Confiabilidade, Eficiência de Performance e Otimização de Custos. Prepare-se para explicar suas decisões, além de demonstrar os endpoints.

## 2. AWS essencial para executar a prova

### Identidade, região e permissões

- Antes de criar qualquer recurso, confirme a identidade e a região. Todos os componentes precisam estar na mesma região, salvo indicação contrária.
- Nos laboratórios, os enunciados citam `LabRole`. Use o papel fornecido e associe-o ao recurso correto (papel de execução da Lambda, papel de tarefa do ECS ou instance profile do processador, conforme o ambiente permitir).
- **Execution role** permite ao serviço iniciar a aplicação, puxar imagem e gravar logs. **Task role** é a identidade da aplicação já em execução para acessar DynamoDB. São papéis com finalidades diferentes.
- Conceda somente as permissões necessárias. Não coloque access key/secret key em código, imagem Docker, histórico de shell ou repositório.

### Rede: desenhe antes de abrir portas

- O **ALB** é o ponto público de entrada do Dia 2. Coloque-o em sub-redes públicas; as tarefas ECS podem ficar em sub-redes privadas.
- Permita entrada pública em 80/443 somente no security group do ALB. Nos security groups das tarefas, permita as portas da aplicação (8000 e 5000) **somente a partir do security group do ALB**.
- No Dia 1, deixe o RDS privado. A porta 5432 deve aceitar conexões somente do security group do processador.
- Recursos em sub-redes privadas precisam de caminho para baixar imagens e enviar logs (NAT Gateway ou VPC endpoints adequados). Se não houver saída, as tarefas podem falhar antes mesmo de iniciar.
- Não torne RDS ou DynamoDB públicos para “resolver” um erro de conectividade. Verifique rota, sub-rede, DNS e regras dos security groups.

### Observabilidade e manutenção

- Centralize logs de Lambda, ECS e processador no CloudWatch Logs; use nomes de grupos previsíveis e consulte logs durante os testes.
- Para ECS, observe estado do serviço, contagem desejada versus em execução, eventos de deployment e estado dos targets no ALB.
- Configure health checks que testem a aplicação real. Um container pode estar `RUNNING` e ainda assim não atender tráfego.
- Em produção, monitore métricas e alarmes (erros, latência, throttling, tarefas indisponíveis, fila/itens pendentes e custos). Na prova, pelo menos demonstre logs e health checks.

## 3. Dia 1 — Pipeline de reclamações (45 minutos)

### Arquitetura e fluxo esperado

`Cliente → API Gateway POST /complaints → Lambda → DynamoDB complaints → processador Go → RDS PostgreSQL`

O endpoint recebe `customer_id`, `message` e `severity`; a Lambda valida, gera `complaint_id`, grava o registro como `processed=false` e retorna o identificador. O processador Go varre itens pendentes a cada cinco segundos, calcula pontuação/categoria, grava no PostgreSQL usando TLS e atualiza o item para `processed=true`.

### Sequência sugerida

#### Fase A — Entrada e persistência (primeiros 15 min)

1. Confirme AWS CLI, identidade e região; defina nomes de recursos consistentes com os verificadores.
2. Crie a tabela DynamoDB `complaints` em `PAY_PER_REQUEST`. O verificador do Dia 1 espera chave composta: `complaint_id` como partition key e `customer_id` como sort key.
3. Implemente ou publique a Lambda (não há código Lambda incluído neste repositório), com papel de execução autorizado a gravar nessa tabela e enviar logs.
4. Publique `POST /complaints` no API Gateway e associe-o à Lambda. Ative/deploy o stage.
5. Teste com JSON válido e inválido. Confirme HTTP 200 para entrada válida, resposta com `complaint_id`, e item no DynamoDB com campos e tipos corretos (`processed` booleano `false`, não string).

Exemplo de payload esperado:

```json
{
  "customer_id": "cust_12345",
  "message": "O aplicativo falha ao abrir",
  "severity": "high"
}
```

Valide também o endpoint de saúde se for exigido pelo avaliador. Não confie apenas no status HTTP: confira o item persistido.

#### Fase B — Processamento e banco (próximos 20 min)

1. Crie PostgreSQL no RDS em sub-redes privadas, classe pequena permitida pelo laboratório e backup conforme o tempo/critério. Não habilite acesso público.
2. Crie ou associe um parameter group que force SSL (`rds.force_ssl=1`) se permitido pelo ambiente. Regras de rede devem aceitar 5432 somente do processador.
3. Implante o processador Go em uma instância EC2 pequena com instance profile, ou no ambiente de execução aprovado no laboratório. Evite credenciais AWS estáticas.
4. Injete `RDS_HOST`, `RDS_USER`, `RDS_PASSWORD`, `RDS_DB`, `AWS_REGION` e `COMPLAINTS_TABLE` como configuração/segredo do ambiente, não em arquivos versionados.
5. Compile para a arquitetura do host de destino e transfira o binário somente após confirmar arquitetura e sistema operacional. A aplicação cria a tabela e índices `processed_complaints` na inicialização.
6. Observe os logs: cliente DynamoDB inicializado, conexão RDS com TLS, tabela pronta, ciclos de varredura e reclamações processadas.
7. Confirme no RDS a linha enriquecida e no DynamoDB `processed=true`. A gravação SQL usa `ON CONFLICT DO NOTHING`, tornando a inserção repetida idempotente para o mesmo `complaint_id`.

O processador existente lê `message`, classifica categorias (`billing`, `technical`, `shipping`, `service`, `other`) e limita `severity_score` ao intervalo 1–10. Ele usa `sslmode=require`, pool SQL e timeout para operações.

#### Fase C — Validação (últimos 10 min)

- Envie um caso de teste novo pela URL do API Gateway.
- Confirme resposta, item DynamoDB antes/depois, linha no PostgreSQL e logs com o mesmo `complaint_id`.
- Faça teste concorrente, começando conservadoramente e aumentando até o requisito (o enunciado cita 50+ requisições simultâneas). Observe erros, latência, throttling e backlog; não inicie carga sem validar o fluxo básico.
- Verifique que itens pendentes continuam sendo processados; se não, confira permissões, formato da chave, expressão de filtro e conectividade.

### O que explicar ao avaliador no Dia 1

- Por que o endpoint desacopla entrada e processamento via DynamoDB: a API responde sem esperar o processamento pesado e os dados permanecem duráveis.
- Como a Lambda valida entrada, gera identificador único e trata erros sem retornar sucesso falso.
- Como o processador evita marcar como processado antes da gravação no RDS; como a chave única e `ON CONFLICT` ajudam em tentativas repetidas.
- Como TLS, parâmetro `rds.force_ssl`, rede privada, papel IAM e CloudWatch protegem e tornam o serviço operável.
- Como escala e custo são tratados: DynamoDB on-demand para demanda variável, instância RDS pequena adequada ao laboratório, limites/paginação e carga observada.

## 4. Dia 2 — Loja em containers no ECS (60 minutos)

### Arquitetura e fluxo esperado

`Cliente → ALB → serviço ECS Fargate Frontend (Flask) → serviço ECS Fargate API (FastAPI) → DynamoDB`

O ALB encaminha tráfego para grupos-alvo apropriados. O Frontend mostra produtos, carrinho e checkout; a API mantém produtos, carrinho e pedidos no DynamoDB. Ambos os containers precisam expor `/health`.

### Sequência sugerida

#### Fase A — API e dados (primeiros 20 min)

1. Crie `products`, `orders` e `cart` com os esquemas do enunciado e capacidade `PAY_PER_REQUEST`.
2. Carregue ao menos cinco produtos de teste. O script `day2/assets/seed-dynamodb.py` carrega vinte produtos em `products`.
3. Configure a API para usar o nome correto das tabelas e a região. O papel da tarefa ECS deve permitir as operações DynamoDB necessárias.
4. Rode localmente e teste `/health`, `/products`, `/products/{id}`, `/cart/{id}`, adicionar/remover do carrinho e criar/consultar pedido.
5. Confira as chaves: `products` usa `product_id`; `orders` usa `order_id` (partition) e `customer_id` (sort); `cart` usa `cart_id` (partition) e `product_id` (sort).

#### Fase B — Frontend e imagens (próximos 20 min)

1. Configure `API_URL` para um endereço alcançável pelo Frontend em execução no ECS. `localhost` dentro de um container aponta para o próprio container, não para a API.
2. Configure `SECRET_KEY` do Flask como segredo e não use o valor de desenvolvimento em ambiente compartilhado.
3. Construa as imagens da API e do Frontend localmente e faça um teste dos containers antes de enviar.
4. Crie repositórios ECR, autentique o Docker no registry da região, faça tag e push das imagens. Use tag imutável/versionada, não dependa somente de `latest`.
5. Verifique que as imagens estão na arquitetura compatível com as tarefas Fargate (`x86_64` é o padrão comum, mas confira o task definition).

#### Fase C — ECS, ALB e prova ponta a ponta (últimos 20 min)

1. Crie o cluster ECS e task definitions `awsvpc` para Fargate, começando por CPU 256 / memória 512 MiB se for compatível com a carga e o laboratório.
2. Defina `executionRoleArn` para puxar imagens e gravar logs; `taskRoleArn` para que a aplicação acesse DynamoDB.
3. Configure log driver `awslogs`, portas 8000 (API) e 5000 (Frontend), variáveis de ambiente e health checks.
4. Crie target groups separados e listeners/regras do ALB para Frontend e API. Configure health check `/health` com a porta e protocolo corretos.
5. Crie os serviços ECS com sub-redes, security groups e contagem desejada de tarefas. Aguarde tasks estáveis e targets `healthy`.
6. Teste usando os endereços expostos: `GET /health` nos dois serviços, catálogo com pelo menos cinco produtos, adicionar produto ao carrinho, abrir checkout e concluir pedido.
7. Confirme o pedido em DynamoDB e consulte logs de ambos os serviços para garantir que o frontend chamou a API correta.

### O que explicar ao avaliador no Dia 2

- O ALB distribui tráfego e usa health checks; ECS mantém a quantidade desejada de tarefas e substitui tarefas que falham.
- ECR guarda imagens versionadas; task definitions descrevem imagem, portas, recursos, papéis, ambiente e logs.
- Fargate elimina a administração direta de hosts; `awsvpc` dá rede própria às tarefas.
- DynamoDB usa chaves adequadas e cobrança on-demand. O frontend nunca deve depender de `localhost` para alcançar outro serviço em produção.
- O que você verificou para provar o fluxo: target health, `/health`, catálogo, carrinho, pedido persistido e logs.

## 5. Manutenção e diagnóstico: roteiro de operação

Siga a ordem **sintoma → camada → evidência → correção → reteste**. Registre o horário, região, recurso e identificador da requisição.

### O endpoint não responde

1. Confirme URL, stage/rota e região.
2. Para Dia 1, verifique deployment/stage do API Gateway, integração e logs da Lambda.
3. Para Dia 2, verifique listener/regra do ALB, target group, targets saudáveis, porta e protocolo do health check.
4. Confirme security groups, rotas e sub-redes. Não abra todas as portas como solução permanente.
5. Teste primeiro `/health`; depois teste uma operação funcional.

### ECS não inicia ou reinicia tarefas

- Leia eventos do serviço: mostram falha ao agendar, puxar imagem, health check ou configuração de rede.
- Consulte logs do container no CloudWatch e a última task stopped reason.
- Confira imagem/tag/arquitetura, `executionRoleArn`, acesso ao ECR, saída para endpoints AWS, memória/CPU e porta.
- Compare `desiredCount`, `runningCount` e `pendingCount`; depois confira o target group.
- Após publicar nova imagem, atualize task definition com uma revisão nova e faça deployment controlado; confirme estabilidade antes de remover a versão anterior.

### Erros de DynamoDB ou dados ausentes

- Confira nome da tabela, região, chave primária/sort key, tipo do atributo e permissões do papel da aplicação.
- Em Dia 1, confira se a Lambda escreve `message` e `processed=false` com os tipos esperados; o processador precisa encontrar o item pela mesma chave.
- Em Dia 2, confira se os dados de seed foram inseridos, se a resposta da API contém produtos e se os itens de carrinho usam as chaves certas.
- Observe throttling, erros de validação e contagem de itens; não aumente capacidade sem evidência.

### Processador não grava no RDS

- Confirme resolução DNS e conectividade TCP 5432 da rede do processador para o RDS.
- Verifique status do RDS, database/user/password e security groups dos dois lados.
- Confirme SSL exigido no servidor e `sslmode=require` na conexão; examine logs do processador e o erro de `PingContext`.
- Verifique permissões SQL, existência da tabela e limites do pool de conexões.
- Após recuperar conectividade, confirme que itens não processados são tentados novamente e não são marcados como concluídos sem persistência.

### Rotina segura de operação

- Acompanhe logs, erros, latência, health checks, tarefas em execução, targets do ALB, itens pendentes e estado/backup do RDS.
- Guarde segredos em mecanismo de segredos do ambiente (por exemplo, Secrets Manager/Parameter Store quando permitido); faça rotação se houver exposição.
- Faça mudanças em revisões de configuração/imagem e valide após cada implantação. Tenha como voltar à última task definition ou imagem estável.
- Após o GameDay, inventarie e remova somente os recursos criados para a prova que não precisam permanecer. RDS, ALB, NAT Gateway e tarefas podem continuar gerando custos.

## 6. Checklist de avaliação antes de entregar

### Para qualquer dia

- [ ] Região e identidade AWS confirmadas; nomes dos recursos consistentes.
- [ ] Fluxo completo testado, não apenas recursos criados.
- [ ] Logs disponíveis no CloudWatch e erros investigados.
- [ ] Health checks respondem com status esperado.
- [ ] Papéis IAM corretos; nenhum segredo em código, imagem ou repositório.
- [ ] Rede restrita e recursos de banco privados.
- [ ] Recursos dimensionados para o requisito; custo e limpeza considerados.
- [ ] Endpoints, IDs e status anotados para demonstrar ao avaliador.

### Dia 1

- [ ] API recebe reclamação válida e valida entrada inválida.
- [ ] DynamoDB tem item com identificador, cliente, mensagem, severidade, timestamp e `processed=false`.
- [ ] Processador lê itens, enriquece, grava no PostgreSQL com TLS e atualiza para `processed=true`.
- [ ] Índices presentes e verificação funcional no RDS executada.
- [ ] Teste de concorrência realizado e backlog/tempo de processamento observados.

### Dia 2

- [ ] Produtos, pedidos e carrinho estão disponíveis no DynamoDB; catálogo tem pelo menos cinco produtos.
- [ ] API e Frontend têm `/health` e tarefas ECS permanecem saudáveis.
- [ ] Imagens estão no ECR e serviços ECS usam task definitions ativas.
- [ ] ALB encaminha aos target groups certos, com targets saudáveis.
- [ ] Fluxo Browse → Cart → Checkout → Order funciona e o pedido persiste.
- [ ] `API_URL` alcança a API pela rede do ECS, não por `localhost`.

## 7. Pontos de atenção nos materiais

Use estes pontos para preparar-se e para não interpretar um resultado automático como prova completa:

1. **Pontuação não é descrita da mesma forma em todos os arquivos.** `MARKING_GUIDE.md` apresenta os desafios como 100 pontos cada e seções com pesos específicos; `USAGE.md` descreve uma planilha única de 100 pontos, dividida em 50 por dia. Confirme com o avaliador qual rubrica e corte (o guia cita 70) serão usados na sua seletiva.
2. **O script do Dia 1 envia `complaint`, mas o enunciado e o processador usam `message`.** O formato efetivo deve ser confirmado com o avaliador/implementação da Lambda; use o contrato oficial e não altere o processador para ocultar a incompatibilidade.
3. **O script do Dia 1 espera chave composta na tabela** (`complaint_id` + `customer_id`), enquanto a descrição de atributos não define explicitamente o esquema da chave. O verificador automatizado exige a chave composta.
4. **O script de pontuação não valida tudo automaticamente.** Há verificações que registram falha explícita e pedem inspeção manual (por exemplo, TLS no código, intervalo do processador, carga e fluxo ponta a ponta). Um `FAIL` nessas linhas não demonstra necessariamente que sua solução falhou.
5. **A contagem de produtos no scorer do Dia 2 parece incompatível com a API existente.** A API retorna objeto `{ "products": [...], "count": n }`, mas o script conta o comprimento do objeto em vez de `products`. Demonstre o catálogo com a resposta real e confirme como a rubrica será avaliada.
6. **Há detalhes de implementação no Dia 2 a corrigir/testar.** A rota de detalhe do Frontend referencia `product.html`, que não aparece entre os templates fornecidos; o scorer pede URLs separadas para API e Frontend, então combine previamente como serão expostas pelo ALB. Teste e corrija esses pontos sem comprometer o fluxo principal.
7. **Os exemplos de health check não são uniformes.** O task definition de exemplo chama `curl`, mas a imagem pode não conter `curl`; os Dockerfiles fornecidos usam Python/`requests`. Garanta que o comando configurado exista na imagem e que o endpoint esteja respondendo.
8. **A configuração TLS do processador merece atenção.** A string usa `sslmode=require`; o código declara uma configuração TLS e um caminho de certificado, mas esses valores não são aplicados à conexão. O requisito do material é TLS obrigatório; se houver tempo e suporte do RDS, prefira validação de CA/hostname conforme política do ambiente.
9. **A descrição do “AI category” é uma classificação por palavras-chave no código**, não um serviço de IA externo. Entregue a classificação funcional e não introduza dependências desnecessárias na prova.

## 8. Como estudar antes da seletiva

1. **Treine AWS CLI e diagnóstico:** identidade/região, DynamoDB, CloudWatch, IAM, RDS, ECR, ECS, ELB e leitura de logs/eventos.
2. **Repita os dois fluxos sem cronômetro**, depois faça ensaios de 45 e 60 minutos. Mantenha uma ordem fixa: dados → aplicação → deploy → health → fluxo fim a fim → logs.
3. **Pratique Docker e ECS:** build, tag/push para ECR, task definition, papéis, variáveis, logs, portas, ALB e atualização de serviço.
4. **Pratique rede AWS:** sub-redes, rotas, NAT/endpoints e security groups com origem por security group.
5. **Prepare uma folha de execução curta**, sem segredos: região, nomes, URLs, comandos de teste e identificadores dos recursos criados.
6. **Treine explicar suas escolhas em voz alta** como se estivesse em uma revisão operacional: o que pode falhar, como você detecta, como recupera e como evita repetir.

O diferencial de uma boa entrega é provar, com evidência, que o sistema funciona e que você sabe mantê-lo — não apenas que os recursos aparecem no console.
