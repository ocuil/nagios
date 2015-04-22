#!/bin/bash
####################################################################################################
# Check para Nagios / Centreon de verificacion del uso de la memoria LIBRE REAL (-/+ buffer/cache) #
# segun las necesidades del Dept. de S.S.O.O.							   #
#												   #
# Dept. de Monitorizacion - Explotacion de Sistemas						   #
#												   #
# Autor	    :	Alejandro Sanchez Losa							   	   #
# Fecha	    :	28 de Febrero del 2012						  	  	   #
# Version   :	1.0										   #
# Licencia  :   GPL										   #
####################################################################################################

# Definimos variables iniciales

warning="10"
critical="5"
debug="n"

# Creamos las funciones que vamos a realizar

help () {

	echo " ==================== "
	echo " == Menu de Ayuda  == "
	echo " ==================== "
	echo ""
	echo " Opciones del check:  "
	echo ""
	echo " -V para definir la version del snmp a usar (no hay para la version 3) "
	echo " -C para definir la comunidad del snmp "
	echo " -H para definir el host "
	echo " -w para definir el umbral de warning "
	echo " -c para definir el umbral de critical "
	echo " -h para sacar este menu "
	echo " -d para activar el modo debug "
	echo ""
	exit 0
}

# Cargamos las varibles relacionadas en los datos de entrada desde el Nagios
# correspondientes a la version de snmp, la comunidad y el host.

while getopts ":V:C:H:w:c:h:d" Option
do
	case $Option in
		V )
			version=$OPTARG
		;;
		C )
			comunidad=$OPTARG
		;;
		H )
			host=$OPTARG
		;;
		w )	
			warning=$OPTARG
		;;
		c )
			critical=$OPTARG
		;;
		h )
			help
		;;
		d )
			debug=y
		;;
	esac
done
shift $(($OPTIND - 1))

# Chequeamos los parametros introducidos necesarios para el chequeo
[ -z $version ] && help
[ -z $comunidad ] && help
[ -z $host ] && help

# Mostramos el debug
[ $debug == "y" ] && echo Version introducida = $version
[ $debug == "y" ] && echo Comunidad introducida = $comunidad
[ $debug == "y" ] && echo Host introducido = $host
[ $debug == "y" ] && echo umbral de warning introducido = $warning
[ $debug == "y" ] && echo umbral de critical introducido = $critical

# Definimos un archivo temporal para el tratamiento de los datos
TMP_FILE=/tmp/check_spl_memory_$RANDOM

# Almacenamos los datos de memoria total y libre ( - / + buffers/cache ) ...
snmpwalk -v $version -c $comunidad $host .1.3.6.1.4.1.2021.4 > $TMP_FILE

# Debug del archivo
[ $debug == "y" ] && echo "" && echo "Contenido del archivo" && cat $TMP_FILE

# Definimos las variables con las que trabajaremos despues
memTotalReal=`cat $TMP_FILE | grep memTotalReal | awk '{ print $4 }'`
memAvailReal=`cat $TMP_FILE | grep memAvailReal | awk '{ print $4 }'`
memBuffer=`cat $TMP_FILE | grep memBuffer | awk '{ print $4 }'`
memCached=`cat $TMP_FILE | grep memCached | awk '{ print $4 }'`

# Definimos las variables que usaremos para los datos extendidos
memTotalSwap=`cat $TMP_FILE | grep memTotalSwap | awk '{ print $4 }'`
memAvailSwap=`cat $TMP_FILE | grep memAvailSwap | awk '{ print $4 }'`
memMinimumSwap=`cat $TMP_FILE | grep memMinimumSwap | awk '{ print $4 }'`

# Debug de los datos de memoria
[ $debug == "y" ] && echo "" && echo "Datos a tratar" && echo "memTotalReal : " $memTotalReal " memAvailReal : " $memAvailReal " memBuffer : " $memBuffer " memCached : " $memCached
[ $debug == "y" ] && echo "" && echo "Datos adicionales" echo "memTotalSwap : " $memTotalSwap " memAvailSwap : " $memAvailSwap " memMinimumSwap : " $memMinimumSwap

# Sacamos el % de uso de la memoria teniendo en cuenta los datos anteriores
# En vez de usar el valor SNMP de memoria libre, vamos a tener en cuenta la
# memoria que estan en buffer y cacheada como memoria disponible para el SO
# ya que estamos tratando con maquinas virtuales y el kernel puede disponer
# de esta memoria "On Demand" para los procesos, de esta forma la veremos como libre.
#
# REGLA DE 3
# SI memTotalReal es el 100
# memSum (Suma de memAvailReal, memBuffer y memCached) es X (memFree)

let "memSum = ${memAvailReal}+${memBuffer}+${memCached}"
let "memFree = 100*${memSum}/${memTotalReal}"

# Debug de los datos tratados
[ $debug == "y" ] && echo memSum = $memSum
[ $debug == "y" ] && echo memFree = $memFree %

# Tratamos los datos para ponerlo en Megas para su representacion grafica
let "memMFree = ${memSum}/1024"
let "memMTotalReal = ${memTotalReal}/1024"
let "memMTotalSwap = ${memTotalSwap}/1024"
let "memMAvailSwap = ${memAvailSwap}/1024"
let "memMMinimumSwap = ${memMinimumSwap}/1024"

# Sacamos por pantalla los datos para que Nagios los recoja y se puedan generar graficas
echo "Memoria libre : $memFree % |memMFree=$memMFree;memMTotalReal=$memMTotalReal;memMTotalSwap=$memMTotalSwap;memMAvailSwap=$memMAvailSwap;memMMinimumSwap=$memMMinimumSwap"

# Eliminamos el archivo temporal
rm -rf $TMP_FILE

# Comparamos los resultados para dar el RC correcto a Nagios
[ $memFree -le $critical ] && exit 2
[ $memFree -le $warning ] && exit 1
[ $memFree -gt $warning ] && exit 0

# Nota importante, dado que estamos contemplando el umbral en la
# cantidad de memoria disponible tenemos el:
#	exit 2 cuando la memoria libre es menor o igual al umbral de critical
#	exit 1 cuando la memoria libre es menor o igual al umbral de warning
#	exit 0 cuando la memoria libre es mayur al umbral de warning
