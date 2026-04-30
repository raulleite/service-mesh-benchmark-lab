# Service Mesh Benchmark

Ambiente reprodutível para medir o custo operacional e de desempenho de service mesh sobre microsserviços HTTP em .NET. O projeto compara Istio e Linkerd em topologias `two-hop` e `three-hop`, gera carga determinística com k6 e consolida RPS, P99, CPU e memória em Prometheus e Grafana.

## Visão geral do projeto

Este repositório entrega um ambiente reprodutível para comparar o custo de operação e desempenho de duas service meshes em microsserviços HTTP em .NET: Istio e Linkerd. O ambiente já foi validado em um desenho com `3 VPS`, com um nó dedicado para cada malha e um terceiro nó de `control-plane` para Grafana e k6. As aplicações disponíveis são `service-entry`, `service-middle`, `service-leaf` e `benchmark-runner`, e as topologias oficiais do benchmark são `two-hop` e `three-hop`.

O dashboard principal é o `comparison-overview`, com leituras live de RPS, P99, CPU e memória. As variáveis ativas são `topology`, `query_step` e `rate_window`. Na prática, a regra operacional validada é simples: `query_step=5s` funciona bem para resolução visual, mas `rate_window` precisa permanecer em janelas seguras de `15s` ou mais. O valor atualmente validado para leitura estável é `40s`.

## Por que este benchmark existe

Microsserviços normalmente melhoram autonomia de times e escalabilidade, mas também deslocam boa parte da complexidade para a rede. Em vez de chamadas locais em memória, a aplicação passa a depender de cadeias distribuídas como:

```text
cliente -> serviço A -> serviço B -> serviço C
```

Quando isso acontece, latência, falhas parciais, observabilidade e identidade entre serviços deixam de ser preocupações acessórias. Elas passam a determinar o comportamento real do sistema sob carga. O service mesh surge justamente nesse ponto: ele cria uma camada padronizada entre serviços para absorver parte dessa complexidade, geralmente no formato:

```text
serviço -> proxy -> rede -> proxy -> serviço
```

Essa camada costuma trazer ganhos importantes em padronização de comunicação, segurança, observabilidade e controle de tráfego. Em troca, ela também introduz custo adicional de CPU, memória, latência por hop e operação. O objetivo deste benchmark é medir esse trade-off em um ambiente controlado, usando a mesma aplicação, a mesma metodologia de carga e o mesmo perfil base de recursos para as duas malhas.

## Quando a malha faz sentido

Em ambientes com muitos serviços, exigência forte de segurança entre workloads, observabilidade mais sofisticada e políticas de tráfego avançadas, o mesh tende a fazer sentido porque a padronização reduz complexidade distribuída dentro das próprias aplicações. Em ambientes menores, com poucos serviços e baixa complexidade operacional, a conta pode se inverter: a infraestrutura adicionada custa mais do que o benefício gerado.

Por isso, a pergunta arquitetural correta não é apenas qual mesh escolher, mas se o sistema realmente precisa de uma malha. Só depois dessa resposta vale comparar qual abordagem entrega o melhor equilíbrio entre controle e overhead.

## Como ler Istio e Linkerd nesta comparação

Este repositório compara duas filosofias diferentes. O Istio prioriza capacidade de controle, políticas avançadas e maior flexibilidade operacional. Essa abordagem costuma fazer mais sentido em ambientes complexos, com times maduros de plataforma e necessidade forte de governança. Em contrapartida, o custo operacional e o overhead sob carga tendem a ser mais perceptíveis, e a análise de métricas exige mais cuidado para separar o comportamento da aplicação do comportamento do sidecar.

O Linkerd segue uma direção mais enxuta. Ele privilegia simplicidade de operação, menor superfície de configuração e menor custo incremental. Isso normalmente o torna mais adequado para times que querem observabilidade e segurança de malha sem assumir o mesmo peso operacional de uma plataforma mais extensa. Em troca, ele oferece menos flexibilidade para cenários com políticas muito avançadas.

## Benchmark de referência

A rodada validada usada como base deste README foi executada com os seguintes parâmetros:

- Início: `2026-04-30T14:11:36Z`
- Perfil: `video1000`
- Warm-up: `20s` a `100 RPS`
- Janela ignorada: `10s`
- Medição: rampa de `0` a `1000 RPS` em passos de `100 RPS`
- Duração por passo: `40s`
- Dashboard: `query_step=5s`, `rate_window=40s`, janela visual de `5m`

O objetivo dessa configuração foi representar uma rampa progressiva até carga alta, preservando leituras suficientes para comparar throughput, latência e custo de recurso no mesmo instante do teste.

### Como interpretar os gráficos

Os quatro painéis mais importantes devem ser lidos em conjunto. `RPS Live` mostra se o throughput final entre as malhas permanece próximo. `P99 Latency Live` revela a qualidade real da resposta sob pressão. `Entry CPU % of limit` separa aplicação e sidecar, permitindo identificar em qual camada a saturação aparece primeiro. `Entry Pod Memory Working Set` complementa a leitura mostrando o footprint consolidado do pod de entrada.

Quando esses quatro sinais são combinados, a leitura deixa de ser apenas “quem entregou mais RPS” e passa a responder a pergunta mais importante: qual malha sustentou a mesma carga com menor custo e melhor latência.

### Resumo consolidado

#### two-hop

| Indicador | Istio | Linkerd |
| --- | ---: | ---: |
| RPS no marco final | 946.0 | 943.7 |
| P99 no marco final | 17.20 ms | 3.63 ms |
| CPU sidecar no marco final | 99.9% | 93.4% |
| CPU app no marco final | 43.6% | 56.4% |
| Memória do pod no marco final | 150.9 MiB | 102.8 MiB |

#### three-hop

| Indicador | Istio | Linkerd |
| --- | ---: | ---: |
| RPS no marco final | 943.5 | 941.0 |
| P99 no marco final | 208.69 ms | 7.40 ms |
| CPU sidecar no marco final | 99.7% | 72.2% |
| CPU app no marco final | 38.9% | 57.0% |
| Memória do pod no marco final | 158.2 MiB | 104.4 MiB |

### Evidências visuais

#### two-hop no marco final

![two-hop 100%](results/reports/benchmark-progress-20260430/screenshots/two-hop-100pct.png)

#### three-hop no marco final

![three-hop 100%](results/reports/benchmark-progress-20260430/screenshots/three-hop-100pct.png)

### Leitura dos resultados

Os resultados mostram que throughput, isoladamente, não explica a diferença de comportamento entre as malhas. Nos marcos finais, Istio e Linkerd terminam com RPS muito próximo nas duas topologias. A divergência relevante aparece no P99, sobretudo em `three-hop`, onde o Istio degrada de forma muito mais agressiva. Esse padrão indica que a aplicação continua entregando volume, mas com custo crescente de cauda de latência.

Ao cruzar P99 com CPU e memória, o efeito fica mais claro. O consumo de memória do pod de entrada permanece consistentemente maior no Istio, e o custo do mesh cresce conforme a cadeia aumenta de `two-hop` para `three-hop`. Isso reforça o ponto central do benchmark: o impacto do dataplane não é constante; ele se torna mais visível à medida que o fluxo ganha mais hops e mais trabalho de proxy por requisição.

### CPU, limite do sidecar e tamanho da máquina

O perfil oficial de recursos desta comparação é fixo e igual para as duas malhas:

- aplicação: `100m` request, `1000m` limit, `128Mi` request, `256Mi` limit
- sidecar: `50m` request, `500m` limit, `64Mi` request, `128Mi` limit
- réplica por serviço: `1`

Com esse perfil, a evidência atual aponta mais fortemente para saturação do sidecar do Istio do que para uma prova direta de falta de CPU global da VPS. Em `two-hop`, o sidecar do Istio fecha em `99.9%` do limite, enquanto a aplicação permanece em `43.6%`. Em `three-hop`, o sidecar fecha em `99.7%`, a aplicação fica em `38.9%` e o P99 sobe para `208.69 ms`. Sob a mesma metodologia e o mesmo perfil de recursos, o Linkerd mantém P99 muito menor e não repete a mesma degradação proporcional em `three-hop`.

Isso não elimina completamente o tamanho da máquina como fator. Uma VPS com pouca folga para kubelet, Prometheus, CNI, ingress e o control plane local pode amplificar o problema. Ainda assim, o que os dados permitem afirmar hoje é mais específico: o sinal principal de degradação está no custo do dataplane do Istio batendo no limite de `500m` do sidecar. O repositório mantém paridade metodológica entre as malhas, mas não versiona o perfil exato de `vCPU` e memória das VPS; por isso, “máquina pequena” continua sendo uma hipótese secundária plausível, não a conclusão principal.

### Conclusão arquitetural

O benchmark converge para uma leitura prática. O custo de service mesh é real e mensurável, cresce com o número de hops e precisa entrar na conta arquitetural desde o início. A escolha entre Istio e Linkerd, portanto, não é uma disputa abstrata entre certo e errado, mas uma decisão de trade-offs entre controle, flexibilidade, simplicidade operacional e overhead.

Antes de adotar qualquer malha, a pergunta correta continua sendo esta:

```text
Você realmente precisa de um service mesh?
```

Se a resposta for sim, então este benchmark ajuda a escolher qual modelo de malha se ajusta melhor ao custo que o seu ambiente consegue absorver.

## Uso rápido em VPS Ubuntu

```sh
chmod +x setup.sh
./setup.sh
```

O script solicita apenas o usuário sudo e a senha de forma segura. Por padrão ele prepara uma VPS Ubuntu com Docker, k3s, Istio ou Linkerd, k6, firewall, build das imagens, deploy dos serviços, observabilidade e, no modo `single-node`, uma execução de benchmark.

Também é possível operar em um desenho com `3 VPS`, usando o mesmo `setup.sh` de forma idempotente por papel:

- `SETUP_ROLE=istio-node`: provisiona a VPS do ambiente Istio com app, k3s, Istio e Prometheus.
- `SETUP_ROLE=linkerd-node`: provisiona a VPS do ambiente Linkerd com app, k3s, Linkerd e Prometheus.
- `SETUP_ROLE=control-plane`: provisiona a VPS de coordenação com Grafana e k6, apontando para os endpoints e Prometheus remotos. Nesse papel, o benchmark não é executado automaticamente por padrão.

Premissa operacional: o script configura apenas o firewall local da VPS com `ufw`. Se a provedora usar firewall externo, security group, ACL de borda ou regras NAT, a liberação pública das portas `30080`, `30081`, `30090` e `30300` precisa ser feita fora do escopo do script.

Parâmetros úteis:

```sh
MESH=istio ./setup.sh
MESH=linkerd TARGET_ENDPOINT=http://127.0.0.1:30080/invoke ./setup.sh
VERBOSE=1 ./setup.sh
```

Exemplo para `3 VPS`:

```sh
SETUP_ROLE=istio-node VERBOSE=1 ./setup.sh
SETUP_ROLE=linkerd-node VERBOSE=1 ./setup.sh
SETUP_ROLE=control-plane \
ISTIO_VPS_IP=10.0.0.11 \
LINKERD_VPS_IP=10.0.0.12 \
VERBOSE=1 ./setup.sh
```

No modo `control-plane`, você também pode informar explicitamente:

```sh
SETUP_ROLE=control-plane \
ISTIO_TARGET_ENDPOINT=http://10.0.0.11:30080/invoke \
LINKERD_TARGET_ENDPOINT=http://10.0.0.12:30082/invoke \
ISTIO_PROMETHEUS_API=http://10.0.0.11:30090/api/v1/query \
LINKERD_PROMETHEUS_API=http://10.0.0.12:30090/api/v1/query \
./setup.sh
```

Para forçar benchmark durante o `setup.sh` do `control-plane`, use `RUN_BENCHMARK_ON_SETUP=1`. Por padrão, o comportamento é apenas provisionar e deixar o ambiente pronto.

Após o provisionamento do `control-plane`, rode o benchmark explicitamente:

```sh
ISTIO_TARGET_ENDPOINT=http://10.0.0.11:30080/invoke \
LINKERD_TARGET_ENDPOINT=http://10.0.0.12:30082/invoke \
ISTIO_PROMETHEUS_API=http://10.0.0.11:30090/api/v1/query \
LINKERD_PROMETHEUS_API=http://10.0.0.12:30090/api/v1/query \
MESH=all ./scripts/run-benchmark.sh
```

Após a liberação externa da porta `30300/tcp` no provedor, o Grafana fica disponível em `http://<ip-publico-da-vps>:30300`.

## Execução local de desenvolvimento

```sh
dotnet restore
dotnet test service-mesh.sln
dotnet run --project apps/service-entry
dotnet run --project apps/service-middle
dotnet run --project apps/service-leaf
dotnet run --project apps/benchmark-runner
```

## Estrutura

- `apps/`: runner e microsserviços .NET.
- `infra/`: manifests Kubernetes, overlays Istio/Linkerd, observabilidade e scripts de ambiente.
- `load/k6/`: cenários de carga oficiais.
- `scripts/`: automação de build, deploy, benchmark e provisionamento Ubuntu.
- `results/runs/`: resultados estruturados por rodada.
- `results/reports/`: relatórios executivos, leituras estruturadas e evidências visuais.
- `specs/`: artefatos Speckit.

## Métricas oficiais e notas operacionais

- Fonte primária de latência P99: k6.
- Fonte secundária de RPS, CPU e memória: Prometheus.
- O scrape atual do Prometheus opera efetivamente em `5s`.
- Por isso, `rate_window=5s` não é confiável para painéis baseados em `rate(...)`.
- A configuração validada do dashboard mantém `query_step=5s` para resolução visual e `rate_window=40s` para cálculo estável.