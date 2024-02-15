#!/usr/bin/env bash
##
# Autor: Thiago Torres Faioli -  A.K.A: 0xttfx  - thiago@tcpip.net.br
# Função: Obter os IPs dos IC Droplets DigitalOcean e inseri-los nos 
# SecurityGroup EC2 das instâncias AWS RDS. 
##
# Versão: 1.0
# Data: 14 de Fevereiro de 2024
# Licença: SPDX-License-Identifier: BSD-3-Clause
#####################################################################
  
  CheckRoot(){
    # Why root?
    if [ "$(id -u)" = 0 ]; then
      echo 
      echo "ERROR: Porque estou sendo executando como root?"
      echo 
      exit 1
    fi
  }
  CheckRoot

  Pidf(){
    # Variável pidfile
    pidfile=/tmp/${0}
    
    # loop para verificação de existência do pidfile e criação em nova execução.
    if [ -f "$pidfile" ]; then
      echo "$pidfile existe. Parando execução"
      exit 1
    else
      # Criando arquivo com o PID atual para indicar o processo em execução.
      echo $$ > "$pidfile"
    fi
  }
  
  # Usando trap para deletar pidfile ao fim da execução do script[ man 5 builtins  ] 
  trap 'rm -f -- "$pidfile"' EXIT
  
  Pidf
  
  # Evitando contratempos
  #set -o errtrace # -E o (SIG)ERR é herda funções, substituições e comandos...
  #set -o errexit  # -e saia imediatamente se um pipeline, lista ou um comando composto falhar
  #set -o nounset  # -u identifica e implica com variáveis não declaradas 
  #set -o pipefail # forçar status code da pipeline ser o status do primeiro comando falho
  set -Eeuo pipefail
  
  # criando trap para identificar onde ocorre um erro
  # BASH_SOURCE guarda o script
  # LINENO linha onde ocorreu o erro
  # FUNCNAME guarda a função onde quebrou 
  # :- usando expansão para definir valor padrão para variável e assim bypassar o nounset
  # inclusive, essa deve ser a técnica para qualquer variável no script 
  trap 'echo "P.Q.P! Rolou algum ERRO na Função: ${FUNCNAME:-}, linha: ${LINENO} :("' ERR
  
  Ajuda(){
     # Display Help
     echo " Scrip para update de IPs DOcean em Security Groups AWS EC2 RDS!"
     echo
     echo " Sintaxe: script [-l|h|v|k|u]"
     echo " Opções:"
     echo " -l        Mostra licença."
     echo " -h        Mostra ajuda."
     echo " -r        remove arquivos orfãos. Útil quando script para antres de apagar arquivos temporários"
     echo " -v        Mostra a versão."
     echo " -u <user> Usuário <user profile aws cli> da API AWS."
     echo
  }
  
  Del(){
    # limpando sujeira
    rm -f /tmp/do-* > /dev/null 2>&1
    rm -f /tmp/sg-* > /dev/null 2>&1
    rm -f /tmp/diff* > /dev/null 2>&1 
  }
  
  BSD(){
    # Display licença
    echo "
    SPDX-License-Identifier: BSD-3-Clause
   
    BSD 3-Clause License
    
    Copyright (c) 2023, the respective contributors, as shown by the AUTHORS file.
    All rights reserved.
  
    
    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:
    
    1. Redistributions of source code must retain the above copyright notice, this
       list of conditions and the following disclaimer.
    
    2. Redistributions in binary form must reproduce the above copyright notice,
       this list of conditions and the following disclaimer in the documentation
       and/or other materials provided with the distribution.
    
    3. Neither the name of the copyright holder nor the names of its
       contributors may be used to endorse or promote products derived from
       this software without specific prior written permission.
    
    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
    AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
    FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
    DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
    SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
    OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
    OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
    "  
    
    echo " "
  }
  
  Versao(){
    echo "
      - v1.0
      - **ipdo-awsrds** versão GA - Disponibilidade Geral!
      - Versão estável para uso em ambiente de produção.
      "
  }


  if [ -z "$*" ]; then 
    sleep 1
    echo
    Ajuda
    echo
    exit 1
  fi
 
  # Lendo opções
  ###########################################################
  while getopts ":hldvu:" option; do
     case $option in
        h) # Mostra Help
           Ajuda
           exit;;
        l) # Mostra licença
           BSD
           exit;;
        d) # Desletando arquivos orfãos
           Del
           exit;;
        v) # Versão
           Versao
           exit;;
        u) # Nome user profile aws cli
           user=$OPTARG;;
       \?) # opção errada
           echo "Opção inválida: -"$OPTARG"" >&2
           exit 1;;
       : ) # Opção errada
  	 echo "Opção -"$OPTARG" requer um argumento." >&2
           exit 1;;
     esac
  done

  User(){
    if [[ -z "${user:-}" ]]; then
      echo  
      echo "Ops! Nome de usuário <user profile aws cli> não informado!"
      echo "Use opção '-u'"
      echo 
      exit 1
    fi
  }
  User

  SGid(){
    #criando array dos IDs dos SecurityGroups EC2 das instâncias AWS RDS
    # ****************************************************************************
    # Quando existem replicas, a listagem do securiy group é compartilhado com o 
    # master! E por isso, a listagem tem item duplicado. Por isso é aplicado sort
    # e uniq na lista para remover duplicidade.
    # ****************************************************************************
    sgid=( "$(aws --profile "${user}" --output text --no-paginate --no-cli-pager \
            rds  describe-db-instances --query "*[].[VpcSecurityGroups]" \
            |awk '{ print $2 }'| sort|uniq)" )
  }
  SGid

  SGtmpf(){
    #criando arquivo temp para cada SecurityGroup EC2 das instâncias AWS RDS
    mapfile -t sg_tmpf < <(for sg in ${sgid[*]}; do
                           mktemp /tmp/"${sg}"-XXX
                         done)
  }
  SGtmpf
  
  SGf(){
    # Gerando lista de IPs das rules /32 de cada SecurityGroups EC2 das instâncias AWS RDS 
    # e inserindo em seus respectivos arquivos temporários
    for sgf in ${sg_tmpf[*]}; do
      sgname=$(sed -E 's/.*(sg-.*)-.*$/\1/' <<< "${sgf}")
      aws --profile "${user}" --output text --no-paginate --no-cli-pager \
      ec2 describe-security-groups --group-id "$sgname" \
      --query "SecurityGroups[].IpPermissions[][].{R:IpRanges}" \
      | grep -E "/32"|  awk '{print $2}'|sed  's/\/32//'|sort |uniq > "${sgf}"
    done
  }
  SGf  

  Rip(){
    # Criando lista de IPs DOcean e populando arquivo temporário
    # criando arquivo temp DOcean
    dotmpf="$(mktemp /tmp/do-XXX)"
  
    # criando array de todos IPs DOcean
    mapfile -t range_ips < <(doctl compute droplet list \
    | awk '{print $3}' |tr -d "[:alpha:]"| grep -Ev "^$" \
    | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
  
    # Populando arquivo temp DOcean com IPs do array para diff
    echo "${range_ips[*]}" | tr ' ' '\n' |sort > "${dotmpf}"
  }
  Rip

  Vai(){
    for lip in ${sg_tmpf[*]}; do
      # criando arquivo temp diff
      tmpdiff="$(mktemp /tmp/diff-XXX)"
      # populano arquivo diff com o diff
      # populano arquivo diff com o diff
      diff -aiw "$lip" "$dotmpf" > "$tmpdiff" || :  
      # criano arrays com resultado do diff! Aqui é definido onde está a diferença!
      # se na lista DO ou na lista AWS.
      if [[ -s "${tmpdiff}" ]]; then
        unset listado
        unset listaaws
        mapfile -t listado < <(cat < "$tmpdiff" | grep -E '>' |grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' || :) 
        mapfile -t listaaws < <(cat < "$tmpdiff" | grep -E '<' |grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' || :) 
        # se ${listaaws[@]} possui IPs que não existem na DOcean. E por isso, esses IPs 
        # serão removidos de cada Security Group EC2 RDS 
        if [[ -n "${listaaws[*]}" ]]; then
          #laço para garantir a execução em todos os grupos
              sed -E 's/.*(sg-.*)-.*$/\1/' <<< "${lip}"| while IFS= read -r g; do
            # laço para remover os IPs dos grupos
            for r in "${listaaws[@]}"; do
              aws ec2 --profile "${user}" revoke-security-group-ingress \
              --group-id "${g}" \
              --protocol tcp \
              --port 5432 \
              --cidr "$r/32"
              #aws ec2 --profile "${user}" revoke-security-group-ingress --group-id "${g}" --ip-permissions IpProtocol=tcp,FromPort=5432,ToPort=5432,IpRanges="[{CidrIp=$r/32}]"
            done
          done
        fi
        # se ${listado[@]} possui IPs que não existem na AWS, esses IPs
        # serão inseridos em cada Security Group EC2 RDS
        if [[ -n "${listado[*]}" ]]; then
          # Laço for para garantir todos os grupos security
          #for h in $(sed -E 's/.*(sg-.*)-.*$/\1/' <<< "${lip}"); do
              sed -E 's/.*(sg-.*)-.*$/\1/' <<< "${lip}"| while IFS= read -r h; do
            # Laço for aninhado para inserção de todos os IPs em cada secutiry group 
            for i in "${listado[@]}"; do
              aws ec2 --profile "${user}" authorize-security-group-ingress \
              --group-id "${h}" \
              --protocol tcp \
              --port 5432 \
              --cidr "$i/32"
                  #aws ec2 --profile "${user}" authorize-security-group-ingress --group-id "${h}" --ip-permissions IpProtocol=tcp,FromPort=5432,ToPort=5432,IpRanges="[{CidrIp=$i/32}]"
            done
          done
        fi
      fi
      rm "${tmpdiff}"
    done
  }
  Vai
  
  RM(){
    # apagando arquivos temporários
    rm -f "${dotmpf}"

    for rm in ${sg_tmpf[*]}; do
      rm -f "${rm}"
    done
  }
  RM

  exit 0
