#!/usr/bin/env bash

# this script downloads amendments from any group of parliamentaries of the French parliament
# we want one amendment per member per line to facilitate analysis
# it's possible to change the data captured in the csv by changing the keys used in define_variables

# NOTE: the code has been refactored for easier re-use, but has yet to to be tested post-refactoring.


define_variables() {
readonly mp_members_header="slug,nom,id_an,mandat_debut,nb_mandats,nom_circo,num_deptmt"
readonly mp_amendments_header="slug,id,auteur_groupe_acronyme,texteloi_id,sort,source,url_nosdeputes"
readonly mp_group="LREM"
}

#store csv headers in files. We will append the actual data after
set_csv_headers() {
    echo "${mp_members_header}" > "${mp_group}"_members.csv
    echo "${mp_amendments_header}" > "${mp_group}"_amendements.csv
}

#fetch LREM member basic info by filtering from the full list of parliament members and store as csv in variable
group_members_to_csv() {
    readonly mp_json_full=$(curl -s https://www.nosdeputes.fr/deputes/enmandat/json)
    readonly mp_csv_group=$(jq -r --arg group "${mp_group}" --arg mpcsv "${mp_members_header}" '
    .deputes[].depute 
    | select(.groupe_sigle == $group) 
    | ($mpcsv|split(",")) as $mp_keys 
    | [ .[ $mp_keys[] ] ] 
    | @csv' <<< "${mp_json_full}"
    | sed 's/\"//g')
}

# modify the names in the second column to fit the API formatting as defined on https://github.com/regardscitoyens/nosdeputes.fr/blob/master/doc/api.md#r%C3%A9sultats-du-moteur-de-recherche
# the sed function is there to remove diacritics and special characters.
amendment_query_prep() {
    readonly mp_names=$(while IFS=, read col1 col2 col3; do 
    echo "${col1},${col2}" 
    | sed -e 'y/áàâäçéèêëîïìôöóùúüñÂÀÄÇÉÈÊËÎÏÔÖÙÜÑ/aaaaceeeeiiiooouuunAAACEEEEIIOOUUN/' -e s/" "/+/g ; 
    done <<< "${mp_csv_group}")
}

# 1. store the number of amendments for this MP based on the api header info
# 2. iterate the variable "i" until the the limit stored previously in "end"
# 3. query the API: we get a list with urls that we need to access to get the amendment data
# 4. the API tells us that the actual url to the file is a bit different because it has changed.
# so we use sed to do that.
# 4b. curl doesn't accept an url as stdin, only parameters, so we need to cheat: we add the string "url=" with sed at the beginning, so it's reocgnized as a parameter by curl then we use curl -K- to accept it as stdin
# 5. the variable col1 will be used to join the LREM member info dataset with the amendment dataset
mp_amendments_to_csvfile() {
while IFS=, read col1 col2 col3
do 
    end=$(curl -s "https://www.nosdeputes.fr/recherche/?object_name=Amendement&tag=parlementaire=$col2&format=json&count=500" | jq '.last_result') 

    for (( i=0;i<$end;i++ )) 
    do 
        curl -s "https://www.nosdeputes.fr/recherche/?object_name=Amendement&tag=parlementaire=$col2&format=json&count=500" \
        | jq --arg num $i '.results[$num|tonumber].document_url' \
        | sed -e "s@//@/@2" -e "s/http/https/" -e "s/^/url=/" | curl -s -K- \
        | jq -r --arg name $col1 --arg mpcsv "${mp_amendments_header}" '.amendement 
        | ($mpcsv|split(",")) as $mp_keys
        | [$name, [ .[ $mp_keys[] ] ]] 
        | @csv' \
        | sed 's/\"//g' >> "${mp_group}"_amendements.csv 
    done 
done <<< "${mp_names}" 
}

group_members_to_csvfile() {
echo "${mp_csv_group}" > "${mp_group}"_members.csv
}

# if needed, a substitution table could be created to change header names from their default
# clearer_csv_headers() {}

main() {
define_variable
set_csv_headers
group_members_to_csv
amendment_query_prep
mp_amendments_to_csvfile
group_members_to_csvfile
# clearer_csv_headers
}