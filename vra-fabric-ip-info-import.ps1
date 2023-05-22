#imports IP information into vSphere network fabrics in vRA

# define vars for environment
$ImportFile = "fabric-ip-info.csv"
$vRAServer = "vra8.domain.com"
$NetworkProfileID = "d33d9120-1b57-4e7e-3B8d-e75e35228078" # ProfileID to be updated
$vRAUser = "user@domain.com"

# Load input file
if (-not(Test-Path -Path $ImportFile -PathType Leaf)) {
    write-host "Input file '$ImportFile' not found..."
    exit
} else {
    $ImportFabricData = import-csv $ImportFile
}

$vRA=connect-vraserver -server $vRAServer -Username "$vRAUser"
if ($null -eq $vRA) {
    write-host "Unable to connect to vRA Server '$vRAServer'..."
    exit
}

# Get Network Profile info and HREFs to it's defined fabrics
$NetworkProfile = Invoke-vRARestMethod -Method GET -URI "/iaas/api/network-profiles/$NetworkProfileID" -WebRequest
$NetworkFabrics =($NetworkProfile.content | ConvertFrom-Json -AsHashtable)._links.'fabric-networks'.hrefs
 
# Build FabricLookup hashtable based on key details from each defined Fabric
# keyed on VLAN ID (from tag on fabric) with HREF to allow update of fabric
$FabricLookup = @{}
write-host "Building Fabric Lookup table..."
$ImportPauseCount = 10  #Execute this many updates and then pause briefly to avoid overloading
$Counter=0  # don't change
foreach ($FabricRef in $NetworkFabrics) {
    $FabricInfo = (Invoke-vRARestMethod -method GET -URI "$FabricRef" -webrequest).content | ConvertFrom-Json -AsHashtable
    $VLAN = $FabricInfo.tags.value
    $FabricLookup.add($VLAN, $FabricRef)
}

foreach ($ImportItem in $ImportFabricData) { 
    $FabricURI=""
    $TargetVLAN = $ImportItem.VLAN_ID
    $FabricURI=$FabricLookup[$TargetVLAN]
    if ($null -eq $FabricURI) {
        write-host Cannot find vRA Network Fabric for import item - VLAN $TargetVLAN
    } else {
        write-host "Found vRA Network fabric for import VLAN $TargetVLAN - updating..."
        
        #Build out separate vars for each update item
        $CIDR = $ImportItem.IP_SUBNET
        $IPGateway = $ImportItem.IP_GATEWAY
        #following could be hard-coded or calculated
        $DNS1 = $ImportItem.DNS1
        $DNS2 = $ImportItem.DNS2
        $DNSSearch = $ImportItem.DNS_SEARCH 
        $Domain = $ImportItem.DOMAIN

#build JSON payload - seems to have syntax requirements to be at line position 1
$json = @"
{
    "domain": "$Domain",
    "defaultGateway": "$IPGateway",
    "dnsServerAddresses": [
        "$DNS1",
        "$DNS2"
    ],
    "dnsSearchDomains": [
        "$DNSSearch"
    ],
    "cidr": "$CIDR"
}
"@
   #Call Update API - use fabric-networks-vsphere for update
   $FabricURI = $FabricURI.replace("fabric-networks","fabric-networks-vsphere")
   $Results=Invoke-vRARestMethod -Method PATCH -URI "$FabricURI" -Body $json
    
    #take a quick break every few imports to avoid overload
        $Counter++
        if ($Counter -gt $ImportPauseCount) {
            write-host "allowing vRA to process (sleeping for 2)"
            sleep 2
            $Counter=0
        }
    }
}

# Clean up
Disconnect-vRAServer -Confirm:$false
