$LOAD_PATH.unshift File.expand_path('../lib/', __FILE__)
require 'parseOptions.rb'
require 'pp'
require 'getCreds.rb'
require 'getFromApi.rb'
require 'json'
require 'csv'
require 'getVm.rb'

class Hash
   def Hash.nest
     Hash.new{|h,k| h[k]=Hash.new(&h.default_proc) }
   end
end


def bToG (b)     
  (((b.to_f/1024/1024/1024) * 100) / 100) 
end

def writecsv(row,hdr)
  if csv_exists?
    CSV.open(Options.outfile, 'a+') { |csv| csv << row }
  else
    CSV.open(Options.outfile, 'wb') do |csv|
      csv << hdr
      csv << row
    end
  end
end

def csv_exists?
  @exists ||= File.file?(Options.outfile)
end

def to_g (b)     
  (((b.to_i/1024/1024/1024) * 100) / 100).round 
end

Creds = getCreds();
Begintime=Time.now
Logtime=Begintime.to_i

# Global options
Options = ParseOptions.parse(ARGV)
def logme(machine,topic,detail)
  time=Time.now
  timepx=time.to_i
  return if topic == "Ping"
  File.open(Logtime.to_s + ".txt", 'a') { |f| f.write("#{time}|#{timepx}|" + machine + "|" + topic + "|" + detail + "\n") }
  puts("#{time}|#{timepx}|" + machine + "|" + topic + "|" + detail)
end
# Grab the SLAHash to make pretty names
if Options.file then
  if Options.assure then
    require 'getVm.rb'
    require 'uri'
    ss = URI.encode(Options.assure.to_s)
    managedId=findVmItemByName(Options.vm,'managedId')
    h=getFromApi("/api/v1/search?managed_id=#{managedId}&query_string=#{ss}")
    h['data'].each do |s|
      puts s['path']
    end
  end
end

if Options.metric then

  if Options.storage then
    h=getFromApi('rubrik',"/api/internal/stats/system_storage")
  end
  if Options.iostat then
    h=getFromApi('rubrik',"/api/internal/cluster/me/io_stats?range=-#{Options.iostat}")
  end
  if Options.archivebw then
    h=getFromApi('rubrik',"/api/internal/stats/archival/bandwidth/time_series?range=-#{Options.archivebw}")
  end
  if Options.snapshotingest then
    h=getFromApi('rubrik',"/api/internal/stats/snapshot_ingest/time_series?range=-#{Options.snapshotingest}")
  end
  if Options.localingest then
    h=getFromApi('rubrik',"/api/internal/stats/local_ingest/time_series?range=-#{Options.localingest}")
  end
  if Options.physicalingest then
    h=getFromApi('rubrik',"/api/internal/stats/physical_ingest/time_series?range=-#{Options.physicalingest}")
  end
  if Options.runway then
    h=getFromApi('rubrik',"/api/internal/stats/runway_remaining")
  end
  if Options.incomingsnaps then
    h=getFromApi('rubrik',"/api/internal/stats/streams/count")
  end
  if Options.blah then
    puts JSON.pretty_generate(h)
  elsif Options.csv then
    json = JSON.parse(h.to_json)
    puts json.first.collect {|k,v| k}.join(',')
    puts json.collect {|node| "#{node.collect{|k,v| v}.join(',')}\n"}.join
  else
    puts h
  end
end

if Options.vmusage then
  vcenters=getFromApi('rubrik',"/api/v1/vmware/vcenter")['data']
  VmwareVCenters = {}     
  vcenters.each do |vcenter|       
    VmwareVCenters[vcenter['id']] = vcenter['hostname']     
  end
  vdatacenters=getFromApi('rubrik',"/api/internal/vmware/data_center")['data']     
  VmwareDatacenters = {}     
  vdatacenters.each do |datacenter|       
    VmwareVCenters[datacenter['id']] = datacenter['name']     
  end
  s=getFromApi('rubrik',"/api/internal/stats/per_vm_storage")['data'] 
  s.each do |r|
    if r['id'].include? "-vm-" then
      vmr=getFromApi('rubrik',"/api/v1/vmware/vm/VirtualMachine:::#{r['id']}")
      r['vmname']=vmr['name']
      r['vcenter']=VmwareVCenters[vmr['vcenterId']]
      r['datacenter']=VmwareVCenters[vmr['currentHost']['datacenterId']]
      if Options.tag then
        require 'vmOperations.rb'
        #vmstuff = getVm(Creds[r['vcenter']],{"objectName" => r['vmname'],"datacenter" => r['datacenter']})
        #vmstuff.config.extraConfig.each { |x| puts "#{x.key}: #{x.value}" }
      	crap=vmwareFromApi(r['vcenter'],"/rest/com/vmware/cis/tagging/tag/")
        #puts vmstuff.tag
  #      vmstuff.config.each { |x| puts "#{x.key}: #{x.value}" }
        #pp vmstuff.config 
        exit
      end
      r.keys.each do |c|
        if c.include? "Bytes" then
          r[c] = to_g(r[c])
        end
      end 
      next if !r['vmname']
      if !Options.outfile & !defined? Done then
        puts r.keys.to_csv
        Done = 1
      end
      if Options.outfile then
        writecsv(r.values,r.keys)
      else
        puts r.values.to_csv
      end
    end
  end
end 


if Options.envision then
  h=getFromApi('rubrik',"/api/internal/report?search_text=#{Options.envision}")
  h['data'].each do |r|
    if r['name'] == Options.envision then
      o=getFromApi('rubrik',"/api/internal/report/#{r['id']}/table")
      hdr = o['columns']
      if !Options.outfile then 
        puts hdr.to_csv
      end
      o['dataGrid'].each do |e|
        if Options.tag then
          vmr=getFromApi('rubrik',"/api/v1/vmware/vm/#{x['ObjectId']}")
          puts vmr['moid']
        end
        if Options.outfile then
          writecsv(e,hdr)
        else
          puts e.to_csv
        end
      end
    end
  end
end

if Options.login then
   require 'getToken.rb'
   token=get_token()
end


if Options.dr then
    require 'getVm.rb'
    require 'uri'
    require 'json'
    require 'setToApi.rb'
    #Get Cluster ID
    clusterInfo=getFromApi("/api/v1/cluster/me")
    id=findVmItemByName(Options.vm,'id')
    #Get Latest Snapshot
    h=getFromApi('rubrik',"/api/v1/vmware/vm/#{id}/snapshot")
    latestSnapshot =  h['data'][0]['id']
    #Get vmWare Hosts for the Cluster
    hostList = Array.new
    o = setToApi('rubrik','/api/v1/vmware/vm/snapshot/' + latestSnapshot + '/instant_recover',{ "vmName" => "#{Options.vm}","hostId" => "#{hostList[0]}","removeNetworkDevices" => true},"post")
    puts '/api/v1/vmware/vm/snapshot/' + latestSnapshot + '/instant_recover'
end

if Options.drcsv then
    require 'CSV'
    require 'getSlaHash.rb'
    require 'getFromApi.rb'
    require 'getVm.rb'
    require 'uri'
    require 'json'
    require 'setToApi.rb'
    require 'vmOperations.rb'
    require 'migrateVM.rb'
    logme("BEGIN","BEGIN",Begintime.to_s)
    logme("Core","Assembling Base Hashes","Started")
  #  (@token,@rubrikhost) = get_token()
    datastores=getFromApi('rubrik',"/api/internal/vmware/datastore")['data']
    logme("Core","Assembling Base Hashes","Infrastructure")
    VmwareDatastores = {}
    datastores.each do |datastore|
      VmwareDatastores[datastore['name']] = datastore['id']
    end
    vcenters=getFromApi('rubrik',"/api/v1/vmware/vcenter")['data']
    VmwareVCenters = {}
    vcenters.each do |vcenter|
      VmwareVCenters[vcenter['id']] = vcenter['hostname']
    end
    vdatacenters=getFromApi('rubrik',"/api/internal/vmware/data_center")['data']
    VmwareDatacenters = {}
    vdatacenters.each do |datacenter|
      VmwareVCenters[datacenter['id']] = datacenter['name']
    end
    clusters=getFromApi('rubrik',"/api/internal/vmware/compute_cluster")['data']
    VmwareClusters = {}
    clusters.each do |cluster|
      VmwareClusters[cluster['id']] = cluster['name']
    end
    hosts=getFromApi('rubrik',"/api/v1/vmware/host")['data']
    temphosts = Hash.nest
    hosts.each do |host|
      hd=getFromApi('rubrik',"/api/v1/vmware/host/#{host['id']}")
      temphosts[VmwareVCenters[hd['datacenter']['vcenterId']]][hd['datacenter']['name']]#[VmwareClusters[hd['computeClusterId']]]
    end
    Infrastructure = temphosts
    hosts.each do |host|
      VmwareHosts[host['id']] = host['name']
      hd=getFromApi('rubrik',"/api/v1/vmware/host/#{host['id']}")
      if Infrastructure[VmwareVCenters[hd['datacenter']['vcenterId']]][hd['datacenter']['name']][VmwareClusters[hd['computeClusterId']]].empty?
        Infrastructure[VmwareVCenters[hd['datacenter']['vcenterId']]][hd['datacenter']['name']][VmwareClusters[hd['computeClusterId']]] = []
      end
      Infrastructure[VmwareVCenters[hd['datacenter']['vcenterId']]][hd['datacenter']['name']][VmwareClusters[hd['computeClusterId']]].push(host['id'])
    end
    logme("Core","Assembling Base Hashes","SLA Domains")
    Sla_hash = getSlaHash()
    logme("Core","Assembling Base Hashes","Succeeded")
    # Read from csv file
    vmlist = CSV.read(Options.infile, {:headers => true})
    pool    = MigrateVM.pool(size: Options.threads.to_i)
    vmlist.map do |row|
      pool.future(:migrate_vm,row)
    end.map(&:value)
  endTimer = Time.now
  runtime = endTimer - Begintime
  logme("END","END",endTimer.to_s + "|" + runtime.to_s)
end

if Options.sla then
  require 'getSlaHash.rb'
  require 'getFromApi.rb'
  require 'getVm.rb'
  sla_hash = getSlaHash()
  if Options.get then
    effectiveSla = sla_hash[findVmItemByName(Options.vm, 'effectiveSlaDomainId')]
    # Get the SLA Domain for node
    puts "#{effectiveSla}"
    exit
  end
  if Options.list then
    listData = getFromApi('rubrik',"/api/v1/vmware/vm?limit=9999")
    listData['data'].each do |s|
      lookupSla = s['effectiveSlaDomainId']
      if lookupSla == 'UNPROTECTED' then
        puts s['name'] + ", " + s['effectiveSlaDomainName'] + ", " + s['effectiveSlaDomainId'] + ", " + s['primaryClusterId']
      else
        slData = getFromApi('rubrik',"/api/v1/sla_domain/#{lookupSla}")
        if s['primaryClusterId'] == slData['primaryClusterId'] then
          result = "Proper SLA Assignment"
        else
          result = "Check SLA Assignemnt!"
        end
        puts s['name'] + ", " + s['effectiveSlaDomainName'] + ", " + s['effectiveSlaDomainId'] + ", " + s['primaryClusterId'] + ", " + slData['primaryClusterId'] + ", " + result
      end
    end
    exit
  end

  vmids = []
  vmids_to_del = []
  vmids_to_del_vmdk = []
  if Options.vm 
    vmids << findVmItemByName(Options.vm, 'id')
  end

  if Options.os || Options.sizerange

    # See if tools is installed on the VM and add to array
    puts "Qualifying SLA Membership"
    vms = getFromApi("/api/v1/vmware/vm?isRelic=false&limit=20&primaryclusterid=local")['data']
    puts "Checking Tools on #{vms.count} VMs"
    vms.each do |vm|
      if vm['toolsInstalled']
        vmids << vm['id']
      end
    end

    puts " - #{vmids.count} of #{vms.count} have VMTools"
    # If we specifc an array of --os
    if Options.os
      puts "Checking OS on #{vmids.count} VMs"
      vmids.each do |i| 
        match = false
        vmos = (findVmItemById(i,'guestOsName'))
        Options.os.each do |o|
          # If OS matches one of the array values
          if vmos && !vmos.empty? && vmos.upcase.include?(o.upcase) 
            match = true
          end
        end
        # Delete from array if there is no OS match
        if !match 
          vmids_to_del << i
        end
      end
      puts " - #{vmids_to_del.count} have failed the OS check for #{Options.os}"
      vmids = vmids.reject{ |e| vmids_to_del.include? e }
    end
    if Options.sizerange 
      puts "Checking VMDK size on #{vmids.count} VMs"
      vmids.each do |i|
        vmdks = bToG(getVmdkSize(i)).round
        if vmdks.between?(Options.sizerange[0].to_i,Options.sizerange[1].to_i)
          next
        else  
          vmids_to_del_vmdk << i
        end
      end
      puts " - #{vmids_to_del_vmdk.count} have failed the VMDK check for #{Options.sizerange} gb total size"
      vmids = vmids.reject{ |e| vmids_to_del_vmdk.include? e }
    end
    puts "Setting #{vmids.count} to #{Options.assure}"
    $v = true
  end
  
  vmids.each do |id|
    if $v
      print "."
    end
    effectiveSla = sla_hash[findVmItemById(id, 'effectiveSlaDomainId')]
    if Options.assure && (effectiveSla != Options.assure) then
      require 'setSla.rb'
      if Options.assure == effectiveSla
        puts "Looks like its set"
      else
        if sla_hash.invert[Options.assure]
          res = setSla(id, sla_hash.invert[Options.assure])
          if !res.nil?
  	    res = JSON.parse(res)
          else
            puts "Rubrik SLA Domain does NOT exist, cannot comply"
          end
        end
      end
    end
  end
  if $v
   puts "Done"
  end
end
