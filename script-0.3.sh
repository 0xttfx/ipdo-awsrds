#!/usr/bin/env bash
##
# Autor: Thiago Torres Faioli -  A.K.A: 0xttfx  - thiago@tcpip.net.br
# Função: Obter os IPs dos IC Droplets DigitalOcean e inseri-los nos 
# SecurityGroup EC2 das instâncias AWS RDS. 
##
# Versão: 0.3
# Data: 11 Out 2023
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

  #criando array dos IDs dos SecurityGroups EC2 das instâncias AWS RDS
  gid=( $(aws rds describe-db-instances \
          --query "*[].[VpcSecurityGroups]" \
          |grep VpcSecurityGroupId \
          |awk '{ print $2 }'|tr -d '"',',') )
  
  #criando arquivo temp AWS
  awstmpf=$(mktemp /tmp/aws-XXX)
  # criando array com IPs das rules /32 dos security groups RDS
  range_rules=( $(aws ec2 describe-security-groups \
      --group-id ${gid[@]} \
      --query "SecurityGroups[].IpPermissions[][].{R:IpRanges}" \
      --output text |grep "/32"|  awk '{print $2}'|sed  's/\/32//'|sort |uniq ) )
  # criando arquivo temp para diff
  echo ${range_rules[@]} | tr ' ' '\n' |sort > ${awstmpf}

  # criando arquivo temp DO
  dotmpf=$(mktemp /tmp/do-XXX)
  # criando array de todos IPs DigitalOcean
  range_ips=( $(doctl compute droplet list | awk '{print $3}' |tr -d [:alpha:]|grep -Ev "^$") )
  # criando arquivo temp para diff
  echo ${range_ips[@]} | tr ' ' '\n' |sort > ${dotmpf}

  diff=( $(diff -Iw ${awstmpf} ${dotmpf}) )
  

  # criano arrays com resultado do diff! Aqui é definido onde está a diferença!
  # se na lista DO ou na lista AWS.
  # Se existem IPs na DO que não existam na AWS, tais IPs serão inseridos na AWS
  # Se existem IPs na AWS que não existam na DO, tais IPs serão removidos da AWS.
  if [[ ! -z "${diff}" ]]
  then
    listado=( $(echo ${diff[@]} |tr ' ' '\n'|grep -E -A1 '>' |grep -Ev '>|---|--|-') ) 2>/dev/null
    listaaws=( $(echo ${diff[@]} |tr ' ' '\n'|grep -E -A1 '<' |grep -Ev '<|---|--|-') ) 2>/dev/null 
  fi	
  
  if [[ ! -z "${listaaws[@]}" ]]
  then	  
    #laço para garantir a execução em todos os grupos
    for g in ${gid[@]}; do
      # laço para remover os IPs dos grupos
      for r in ${listaaws[@]};do
        aws ec2 revoke-security-group-ingress \
        --group-id ${g} \
        --protocol tcp \
        --port 5432 \
        --cidr ${r}/32
      done
    done
  fi
  
  if [[ ! -z "${listado[@]}" ]]
  then
    # Laço for para garantir todos os grupos security
    for g in ${gid[@]}; do
      # Laço for aninhado para inserção de todos os IPs em cada secutiry group 
      for i in ${listado[@]}; do
      aws ec2 authorize-security-group-ingress \
      --group-id ${g} \
      --protocol tcp \
      --port 5432 \
      --cidr ${i}/32
      done
    done
  fi

  # apagando arquivos temporários
  rm ${dotmpf}
  rm ${awstmpf}

exit 0
