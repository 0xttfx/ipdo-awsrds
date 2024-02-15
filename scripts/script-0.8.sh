#!/usr/bin/env bash
##
# Autor: Thiago Torres Faioli -  A.K.A: 0xttfx  - thiago@tcpip.net.br
# Função: Obter os IPs dos IC Droplets DigitalOcean e inseri-los nos 
# SecurityGroup EC2 das instâncias AWS RDS. 
##
# Versão: 0.8
# Data: 10 de Fevereiro de 2024
# Licença: SPDX-License-Identifier: BSD-3-Clause
#####################################################################

#licença:
#   SPDX-License-Identifier: BSD-3-Clause
#
#   BSD 3-Clause License
#
#   Copyright (c) 2018, the respective contributors, as shown by the AUTHORS file.
#   All rights reserved.
#
#   Redistribution and use in source and binary forms, with or without
#   modification, are permitted provided that the following conditions are met:
#
#   * Redistributions of source code must retain the above copyright notice, this
#     list of conditions and the following disclaimer.
#
#   * Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#
#   * Neither the name of the copyright holder nor the names of its
#     contributors may be used to endorse or promote products derived from
#     this software without specific prior written permission.
#
#   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#   AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#   IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#   DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
#   FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
#   DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
#   SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
#   CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
#   OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
#####
  
  # Variável pidfile
  pidfile=/tmp/script-0.8.pid
  
  # loop para verificação de existência do pidfile e criação em nova execução.
  if [ -f "$pidfile" ]; then
    echo "$pidfile existe. Parando execução"
    exit 1
  else
    echo "$pidfile não existe."
    # Criando arquivo com o PID atual para indicar o processo em execução.
    echo $$ > "$pidfile"
  fi
  
  # Usando trap para deletar pidfile ao fim da execução do script[ man 7 builtins  ] 
  trap 'rm -f -- "$pidfile"' EXIT
  
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
  trap 'echo "ERRO EM: ${BASH_SOURCE}:${LINENO}:${FUNCNAME:-}"' ERR

  # limpando sujeira
  rm -f /tmp/do-*
  rm -f /tmp/sg-*
  rm -f /tmp/diff* 

  # Função para verificação de erro
  # if_ok() {
  #   if [ $? != 0 ]; then
  #     "$@"
  #   fi
  # }
  #  
  # if_ok() {
  #   if [ $? -eq 0 ]; then
  #     echo "última execução ok!"
  #   else
  #     echo "falha na última execução"
  #     exit 1
  #   fi
  # }

  # user profile aws cli
  user=oper
  if [[ -z "${user}" ]]; then
    echo 
    echo "Variável 'user' não configurada!"
    echo "Edite o script ${0} e declare o nome do usuário IAM"
    echo
    exit 1
  fi


  #criando array dos IDs dos SecurityGroups EC2 das instâncias AWS RDS
  # ****************************************************************************
  # * Das 9 instâncias RDS existentes, 1 é replica e por isso, o securiy group é
  # * compartilhado com o master! Por isso é aplicado sort e uniq na lista para
  # * remover duplicidade.
  # *****************************************************************************
  sgid=( "$(aws --profile "$user" --output text --no-paginate --no-cli-pager \
          rds  describe-db-instances --query "*[].[VpcSecurityGroups]" \
          |awk '{ print $2 }'| sort|uniq)" )

  
  #criando arquivo temp para cada SecurityGroup EC2 das instâncias AWS RDS
  mapfile -t sg_tmpf < <(for sg in ${sgid[*]}; do mktemp /tmp/"${sg}"-XXX; done)
  
  # Gerando lista de IPs das rules /32 de cada SecurityGroups EC2 das instâncias AWS RDS 
  # e inserindo em seus respectivos arquivos temporários
  for sgf in ${sg_tmpf[*]}; do
    sgname=$(sed -E 's/.*(sg-.*)-.*$/\1/' <<< "${sgf}")
    aws --profile "${user}" --output text --no-paginate --no-cli-pager \
    ec2 describe-security-groups --group-id "$sgname" \
    --query "SecurityGroups[].IpPermissions[][].{R:IpRanges}" \
    | grep -E "/32"|  awk '{print $2}'|sed  's/\/32//'|sort |uniq > "${sgf}"
  done

  # criando arquivo temp DOcean
  dotmpf="$(mktemp /tmp/do-XXX)"
  
  # criando array de todos IPs DOcean
  mapfile -t range_ips < <(doctl compute droplet list | awk '{print $3}' |tr -d "[:alpha:]"| grep -Ev "^$"| grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
  
  # Populando arquivo temp DOcean com IPs do array para diff
  echo "${range_ips[*]}" | tr ' ' '\n' |sort > "${dotmpf}"

  for lip in ${sg_tmpf[*]}; do
    # criando arquivo temp diff
    tmpdiff="$(mktemp /tmp/diff-XXX)"
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
            #aws --debug ec2 --profile "${user}" revoke-security-group-ingress --group-id "${g}" --ip-permissions IpProtocol=tcp,FromPort=5432,ToPort=5432,IpRanges="[{CidrIp=$r/32}]"
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
	        #aws --debug ec2 --profile "${user}" authorize-security-group-ingress --group-id "${h}" --ip-permissions IpProtocol=tcp,FromPort=5432,ToPort=5432,IpRanges="[{CidrIp=$i/32}]"
          done
        done
      fi
    fi
    rm "${tmpdiff}"
  done
  # apagando arquivos temporários
  rm -f "${dotmpf}"

  for rm in ${sg_tmpf[*]}; do
    rm -f "${rm}"
  done

exit 0