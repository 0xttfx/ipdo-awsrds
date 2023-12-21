#!/usr/bin/env bash
##
# Autor: Thiago Torres Faioli -  A.K.A: 0xttfx  - thiago@tcpip.net.br
# Função: Obter os IPs dos IC Droplets DigitalOcean e inseri-los nos 
# SecurityGroup EC2 das instâncias AWS RDS. 
##
# Versão: 0.5
# Data: 19 Dez 2023
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

  # Why root?
  CheckRoot(){
    if [ `id -u` = 0 ]; then
      echo 
      echo "ERROR: Why are you running this shit as root?"
      echo
      exit 1
    fi
  }
  CheckRoot
 
  # user profile aws cli
  user=
  if [[ -z "${user}" ]]; then
    echo
    echo "Variável 'user' não configurada!"
    echo "Edite o script ${0} e declare o nome do usuário IAM"
    echo
    exit 1
  fi

  #criando array dos IDs dos SecurityGroups EC2 das instâncias AWS RDS
  # ****************************************************************************
  # * Quando 1 instâncias RDS existente é replica, o securiy group é compartilhado 
  # * com o master! Por isso é aplicado sort e uniq na lista para
  # * remover duplicidade.
  # *****************************************************************************
  sgid=( $(aws --profile ${user} --output text --no-paginate --no-cli-pager \
          rds  describe-db-instances --query "*[].[VpcSecurityGroups]" \
          |awk '{ print $2 }'| sort|uniq) )

  #criando arquivo temp para cada SecurityGroup EC2 das instâncias AWS RDS
  sg_tmpf=( $(for sg in ${sgid[@]}; do
         	      mktemp /tmp/${sg}-XXX
                  done) )

  # Gerando lista de IPs das rules /32 de cada SecurityGroups EC2 das instâncias AWS RDS
  # e inserindo em seus respectivos arquivos temporários
  for sgf in ${sg_tmpf[@]}; do
    aws --profile ${user} --output text --no-paginate --no-cli-pager \
    ec2 describe-security-groups --group-id $(sed -E 's/.*(sg-.*)-.*$/\1/' <<< ${sgf}) \
    --query "SecurityGroups[].IpPermissions[][].{R:IpRanges}" \
    | grep -E "/32"|  awk '{print $2}'|sed  's/\/32//'|sort |uniq > ${sgf}
  done

  # criando arquivo temp DOcean
  dotmpf=$(mktemp /tmp/do-XXX)
  # criando array de todos IPs DOcean
  range_ips=( $(doctl compute droplet list | awk '{print $3}' |tr -d [:alpha:]|grep -Ev "^$") )
  # Populando arquivo temp DOcean com IPs do array para diff
  echo ${range_ips[@]} | tr ' ' '\n' |sort > ${dotmpf}


  for lip in ${sg_tmpf[@]}; do
    unset diff
    diff=( $(diff -Iw ${lip} ${dotmpf}) )
    # criano arrays com resultado do diff! Aqui é definido onde está a diferença!
    # se na lista DO ou na lista AWS.
    if [[ ! -z "${diff}" ]]; then
      unset listado
      unset listaaws
      listado=( $(echo ${diff[@]} |tr ' ' '\n'|grep -E -A1 '>' |grep -Ev '>|---|--|-') ) 2>/dev/null
      listaaws=( $(echo ${diff[@]} |tr ' ' '\n'|grep -E -A1 '<' |grep -Ev '<|---|--|-') ) 2>/dev/null
      # se ${listaaws[@]} possui IPs que não existem na DOcean. E por isso, esses IPs
      # serão removidos de cada Security Group EC2 RDS
      if [[ ! -z "${listaaws[@]}" ]]; then
        #laço para garantir a execução em todos os grupos
        for g in $(sed -E 's/.*(sg-.*)-.*$/\1/' <<< ${lip}); do
          # laço para remover os IPs dos grupos
          for r in ${listaaws[@]}; do
            aws ec2 --profile ${user} revoke-security-group-ingress \
            --group-id ${g} \
            --protocol tcp \
            --port 5432 \
            --cidr ${r}/32
          done
        done
      fi
      # se ${listado[@]} possui IPs que não existem na AWS, esses IPs
      # serão inseridos em cada Security Group EC2 RDS
      if [[ ! -z "${listado[@]}" ]]; then
        # Laço for para garantir todos os grupos security
        for g in $(sed -E 's/.*(sg-.*)-.*$/\1/' <<< ${lip}); do
          # Laço for aninhado para inserção de todos os IPs em cada secutiry group
          for i in ${listado[@]}; do
            aws ec2 --profile ${user} authorize-security-group-ingress \
            --group-id ${g} \
            --protocol tcp \
            --port 5432 \
            --cidr ${i}/32
          done
        done
      fi
    fi
  done
  # apagando arquivos temporários
  rm ${dotmpf}
  rm /tmp/sg-*
exit 0

