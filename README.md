# IPDropSecGroupAWSEC2RDS

## Função
 Scrip bash para descoberta de IPs de Droplets Nodes dos clusters Kubernetes e inserção destes IPs, no security group EC2 das instâncias AWS RDS.

## Dependências

- AWS CLI
  - [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
  - [EC2](https://docs.aws.amazon.com/cli/latest/reference/ec2/)
    - [API authorize-security-group-ingress](https://docs.aws.amazon.com/cli/latest/reference/ec2/authorize-security-group-ingress.html)
    - [API describe-security-groups](https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-security-groups.html)
  - [RDS](https://docs.aws.amazon.com/cli/latest/reference/rds/)
    - [API describe-db-instances](https://docs.aws.amazon.com/cli/latest/reference/rds/describe-db-instances.html)
- DigitalOcean CLI
  - [DO CLI](https://docs.digitalocean.com/reference/doctl/how-to/install/)
    - [API compute](https://docs.digitalocean.com/reference/doctl/reference/compute/)

## Executando

 Crie diretório `tools` em  `/usr/local` 
```
mkdir -p /usr/local/tools/log && cd /usr/local/tools/ && \
git clone git@github.com:0xttfx/ip-do_aws-rds.git && cd ip-*
```

 Não há argumentos, bastando executar o .sh
```
./script-0.3.sh
```

## Automação 

 Para automação da execução, adicione a seguinte linha na cron, para uma execução a cada 6 horas, ou modifique...
 Devido ao update dos nós dos clusters, que alteram os seus IPs, o script será executado a cada 2 mintuos, afim de evitar indisponibilidade dos sistemas.
```
*/2 * * * * 	user	/usr/bin/bash -x /usr/local/tools/ip-do_aws-rds/script-0.3.sh >> /usr/local/tools/log/exec-script-0.3-$(date --date="today" +\%d\%m\%Y_\%H\%M).log 2>&1
0 0 * * *       user	find /usr/local/tools/log -type f -mtime +3 -name '*.log' -exec rm {} +
```
