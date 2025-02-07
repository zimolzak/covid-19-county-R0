#!/bin/sh
URL=https://www.dshs.state.tx.us/coronavirus/TexasCOVID19DailyCountyCaseCountData.xlsx
# change to the current directory of the script
cd "${0%/*}"
datafile="TSHS_CaseCountData/Texas COVID-19 Case Count Data by County.xlsx"
tmcdatafile="TMC/Total Tests by Date and Source.xlsx"
sumfile=TSHS_CaseCountData/data.md5
tmcsumfile=TMC/data.md5

# first get the file
echo "Download data"
wget -q $URL -O "$datafile"

# in case upstream has been updated
git pull

# calculate md5
if [ -x "$(command -v md5sum)" ]; then
  newsum=$(md5sum "$datafile")
  newtmcsum=$(md5sum "$tmcdatafile")
else
  newsum=$(md5 "$datafile")
  newtmcsum=$(md5 "$tmcdatafile")
fi

# create md5 if not exist
if [ -f $sumfile ] && [ -f $tmcsumfile ]; then
    result=`md5sum -c  --quiet $sumfile`
    tmcresult=`md5sum -c  --quiet $tmcsumfile`
    if [ "$result" == "" ]  && [ "$tmcresult" == "" ] ; then
      echo "Data has not been changed"
      exit 0
    fi
fi

echo $newsum > $sumfile
echo $newtmcsum > $tmcsumfile
echo "Update md5 file"

# build docker image if has not existed
if [[ "$(docker images -q covid19-r0-sos 2> /dev/null)" == "" ]]; then
   docker build . -t covid19-r0-sos
fi


# process data
docker run --rm -i -v $(pwd):/covid-19-county-R0 covid19-r0-sos sh -c 'cd /covid-19-county-R0/TSHS_CaseCountData; Rscript code.r'
docker run --rm -i -v $(pwd):/covid-19-county-R0 covid19-r0-sos sh -c 'cd /covid-19-county-R0/; papermill  --engine sos "Realtime R0_sos.ipynb" Realtime_updated.ipynb -p param_days 10 -p param_std 2.2 -p param_sigma 0.08'

# update title with the current date and convert to HTML file
sed -i.bak -E "s/in Texas \(Until .+\)/in Texas \(Until $(date +"%b %d")\)/" Realtime_updated.ipynb
docker run --rm -i -v $(pwd):/covid-19-county-R0 covid19-r0-sos sh -c 'cd /covid-19-county-R0/; sos convert Realtime_updated.ipynb index.html --template sos-report-only'

# move updated HTML file to webserver
git commit . -m 'Update report'
git push
[ -d /var/www/web/sites/default/files ] && cp index.html "/var/www/web/sites/default/files/r0.html"
