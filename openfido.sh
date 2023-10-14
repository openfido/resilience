#!/bin/sh
#
# GridLAB-D environment for OpenFIDO
#

TEMPLATE=anticipation

error()
{
    echo '*** ABNORMAL TERMINATION ***'
    echo 'See error Console Output stderr for details.'
    echo "See https://github.com/openfido/loadshape for help"
    exit 1
}



trap on_error 1 2 3 4 6 7 8 11 13 14 15

set -x # print commands
set -e # exit on error
set -u # nounset enabled

export GLPATH=/usr/local/opt/gridlabd/current/share/gridlabd/template/US/CA/SLAC/anticipation

rm -rf $GLPATH

# configure template 
gridlabd template config set GITUSER arras-energy
gridlabd template config set GITREPO gridlabd-template
gridlabd template config set GITBRANCH develop-utilities
gridlabd template get $TEMPLATE

file_list=$(ls -l $GLPATH)
echo "$file_list"

if [ ! -f "/usr/local/bin/gridlabd" ]; then
    echo "ERROR [openfido.sh]: '/usr/local/bin/gridlabd' not found" > /dev/stderr
    error
elif [ ! -f "$OPENFIDO_INPUT/config.csv" ]; then
    OPTIONS=$(cd $OPENFIDO_INPUT; ls -1 | tr '\n' ' ')
    if [ ! -z "$OPTIONS" ]; then
        echo "WARNING [openfido.sh]: '$OPENFIDO_INPUT/config.csv' not found, using all input files by default" > /dev/stderr
    else
        echo "ERROR [openfido.sh]: no input files"
        error
    fi
else
    OPTIONS=$(cd $OPENFIDO_INPUT ; cat config.csv | tr '\n' ' ')
fi

echo '*** INPUTS ***'
ls -l $OPENFIDO_INPUT

if [ -f template.rc ]; then
    TEMPLATE_CFG=$(cat template.cfg | tr '\n' ' ' )
else
    TEMPLATE_CFG=""
fi

cd $OPENFIDO_OUTPUT
cp -R $OPENFIDO_INPUT/* . #WHY?


# process config file
if [ -e "config.csv" ]; then
    # ANALYSIS=$(grep ^ANALYSIS, "config.csv" | cut -f2- -d, | tr ',' ' ')
    INPUT_POLE_FILE=$(grep ^INPUT_POLE_FILE, "config.csv" | cut -f2- -d, | tr ',' ' ')
    # INPUT_VEG_FILE=$(grep ^INPUT_VEG_FILE, "config.csv" | cut -f2- -d, | tr ',' ' ')
    INPUT_EQUIPMENT_FILE=$(grep ^INPUT_EQUIPMENT_FILE, "config.csv" | cut -f2- -d, | tr ',' ' ')
    STARTTIME=$(grep ^STARTTIME, "config.csv" | cut -f2- -d, | tr ',' ' ')
    STOPTIME=$(grep ^STOPTIME, "config.csv" | cut -f2- -d, | tr ',' ' ')
    TIMEZONE=$(grep ^TIMEZONE, "config.csv" | cut -f2- -d, | tr ',' ' ')
    # MODEL_NAME=$(grep ^MODEL_NAME, "config.csv" | cut -f2- -d, | tr ',' ' ')
    USECASE=$(grep ^USECASE, "config.csv" | cut -f2- -d, | tr ',' ' ')
    WIND_SPEED=$(grep ^WIND_SPEED, "config.csv" | cut -f2- -d, | tr ',' ' ')
    # WIND_SPEED_INC=$(grep ^WIND_SPEED_INC, "config.csv" | cut -f2- -d, | tr ',' ' ')
    # WIND_DIR=$(grep ^WIND_DIR, "config.csv" | cut -f2- -d, | tr ',' ' ')
    # WIND_DIR_INC=$(grep ^WIND_DIR_INC, "config.csv" | cut -f2- -d, | tr ',' ' ')
    # POLE_DIV=$(grep ^POLE_DIV, "config.csv" | cut -f2- -d, | tr ',' ' ')
    echo "Config settings:"
    echo "  POLE_DATA = ${INPUT_POLE_FILE:-}"
else
    echo "No 'config.csv', using default settings:"
    echo "USECASE = 'BULK'"
    USECASE="BULK"
fi

if [ $USECASE = "BULK" ]; then
    echo "Running bulk pole analysis."
    # Convert XLSX to CSV + model wrapper 
    echo "converting XLSX to CSV"
    gridlabd convert -i "poles:$INPUT_POLE_FILE" -o POLES.csv -f xlsx-spida -t csv-geodata include_dummy_network=True include_weather=weather
    # gridlabd convert -i "poles:$INPUT_POLE_FILE,equipment:$INPUT_EQUIPMENT_FILE" -o $OPENFIDO_OUTPUT/POLES.csv -f xlsx-spida -t csv-geodata include_dummy_network=True include_weather=weather

    echo "converting CSV to GLM"
    gridlabd convert -i POLES.csv -o POLES.glm -f csv-table -t glm-object module=powerflow 
    echo "Running the pole analysis"
    # cd /usr/local/opt/gridlabd/current/share/gridlabd/template/US/CA/SLAC/anticipation
    gridlabd --verbose -D output_message_context=NONE -D starttime=$STARTTIME -D stoptime=$STOPTIME -D timezone=$TIMEZONE -D WIND_SPEED=$WIND_SPEED /usr/local/opt/gridlabd/current/share/gridlabd/template/US/CA/SLAC/anticipation/main_bulk.glm POLES.glm 
    template_file_list=$(ls -l)
    echo "$template_file_list"
    # cp -R "/usr/local/opt/gridlabd/current/share/gridlabd/template/US/CA/SLAC/anticipation/pole_status.csv" "$OPENFIDO_OUTPUT/pole_status.csv"
    cd -
fi


if [ $USECASE = "INCLUDE_NETWORK" ]; then
    echo "Running analysis with network"
    # Convert Model to CSV 
    gridlabd -C $OPENFIDO_INPUT/$INPUT_POLE_FILE convert_to_csv.glm   
    # Convert XLSX to CSV + model wrapper 
    gridlabd convert -i "poles:$INPUT_POLE_FILE,equipment:$INPUT_EQUIPMENT_FILE" -o $OPENFIDO_OUTPUT/$MODEL_NAME.csv -f xlsx-spida -t csv-geodata include_network=True #options include network
    # Add loads 
    # gridlabd create_childs ...

    # Add meters 
    # gridlabd create_meters ...

    # Connect AMI
    # gridlabd convert -i cardinal_AMI.csv -o ami-players.glm -f csv-ami -t glm-player

    # RUN THE MODEL 
    # gridlabd 
fi


if [ $USECASE = "INCLUDE_VEGETATION" ]; then 
    echo "Running vegetation analysis."
    # gridlabd convert -i "poles:$INPUT_POLE_FILE,equipment:$INPUT_EQUIPMENT_FILE" -o ./output/$MODEL_NAME.csv -f xlsx-spida -t csv-geodata 
    # gridlabd python veg_data_preprocess.py
    gridlabd geodata merge -D elevation $INPUT_POLE_FILE -r 30 | gridlabd geodata merge -D vegetation >$OPENFIDO_OUTPUT/path_vege.csv
    gridlabd python /usr/local/opt/gridlabd/current/share/gridlabd/template/US/CA/SLAC/anticipation/add_info.py # this needs to get integrated into the gridlabd source code
    gridlabd geodata merge -D powerline $OPENFIDO_OUTPUT/path_vege.csv --cable_type="TACSR/AC 610mm^2" >$OPENFIDO_OUTPUT/path_result.csv
    gridlabd python /usr/local/opt/gridlabd/current/share/gridlabd/template/US/CA/SLAC/anticipation/folium_data.py
    gridlabd /usr/local/opt/gridlabd/current/share/gridlabd/template/US/CA/SLAC/anticipation/folium.glm -D html_save_options="--cluster" -o $OPENFIDO_OUTPUT/folium.html
fi


# if [ "$ANALYSIS" = "vegetation_analysis" ]; then 
#     echo "Running vegetation analysis, only."
#     gridlabd geodata merge -D elevation $OPENFIDO_INPUT/$POLE_DATA -r 30 | gridlabd geodata merge -D vegetation >$OPENFIDO_OUTPUT/path_vege.csv
#     python3 /usr/local/share/gridlabd/template/US/CA/SLAC/anticipation/add_info.py # this needs to get integrated into the gridlabd source code
#     gridlabd geodata merge -D powerline $OPENFIDO_OUTPUT/path_vege.csv --cable_type="TACSR/AC 610mm^2" >$OPENFIDO_OUTPUT/path_result.csv
#     python3 /usr/local/share/gridlabd/template/US/CA/SLAC/anticipation/folium_data.py
#     gridlabd /usr/local/share/gridlabd/template/US/CA/SLAC/anticipation/folium.glm -D html_save_options="--cluster" -o $OPENFIDO_OUTPUT/folium.html
# elif [ "$ANALYSIS" = "pole_analysis" ]; then 

#     if [ "$USECASE" = "--" ]; then
#         echo "ERROR [openfido.sh]: Please set a usecase for pole analysis" > /dev/stderr
#         error
#     fi
    
#     CSV_NAME="poles_w_equip_and_network"
#     GLM_NAME="network"
#     USECASES=("loading_scenario" "critical_speed" "worst_angle")
#     RESULT_NAME="results"
#     POLE_OPTION=""
#     if [[ -n "$POLE_NAME" ]]; then
#         POLE_OPTION="--poles_selected=pole_$POLE_NAME"
#         POLE_NAME="$POLE_NAME\_"
#     fi

#     echo "Converting SPIDAcalc excel report to CSV"
#     gridlabd convert $OPENFIDO_INPUT/$POLE_DATA $OPENFIDO_OUTPUT/$CSV_NAME.csv -f xls-spida -t csv-geodata extract_equipment=yes include_network=yes
#     echo "Converting CSV to GLM"
#     gridlabd -D csv_load_options="-f table -t object -M powerflow -o $OPENFIDO_OUTPUT/$GLM_NAME.glm" $OPENFIDO_OUTPUT/$CSV_NAME.csv
#     echo "Pole analysis on GLM file"
#     if [[ "$USECASE" = "all" ]]; then
#         for option in "${USECASES[@]}"; do
#         echo "Running $option usecase"
#             gridlabd pole_analysis $OPENFIDO_OUTPUT/$GLM_NAME.glm --analysis=$option --wind_speed=$WIND_SPEED --wind_direction=$WIND_DIR --direction_increment=$WIND_DIR_INC --speed_increment=$WIND_SPEED_INC --segment=$POLE_DIV --output=$OPENFIDO_OUTPUT/$RESULT_NAME\_$POLE_NAME$option.csv $POLE_OPTION
#         done
#     else
#         gridlabd pole_analysis $OPENFIDO_OUTPUT/$GLM_NAME.glm --analysis=$USECASE --wind_speed=$WIND_SPEED --wind_direction=$WIND_DIR --direction_increment=$WIND_DIR_INC --speed_increment=$WIND_SPEED_INC --segment=$POLE_DIV --output=$OPENFIDO_OUTPUT/$RESULT_NAME\_$POLE_NAME$USECASE.csv $POLE_OPTION
#     fi
# fi 

# ( gridlabd template $TEMPLATE_CFG get $TEMPLATE && gridlabd --redirect all $OPTIONS -t $TEMPLATE  ) || error

echo '*** OUTPUTS ***'
output_list=$(ls -l $OPENFIDO_OUTPUT)
echo "$output_list"


echo '*** RUN COMPLETE ***'
echo 'See Data Visualization and Artifacts for results.'

echo '*** END ***'
