require 'rubygems'
require 'neography'
require 'sinatra'
require 'open-uri'
require 'zlib'
require 'yajl'
require 'set'
require 'crunchbase'

Crunchbase::API.key = 'wsg8mtrjwvrjyggyzk2kybxp'

def create_graph
  companies = []
  people    = []
  fos       = []
  tags      = Set.new
  employees = []
  competes  = []
  invested  = Set.new
  tagged    = []
  
  puts "Downloading Companies"
  all_companies = Crunchbase::Company.all
  all_companies.each do |ac|
    begin
      file = "crunchbase/companies/#{ac.permalink}"
      if File.exist?(file)
        company = Marshal::load(File.open(file, 'r'))
      else
        company = ac.entity
        File.open(file, 'wb') { |fp| fp.write(Marshal::dump(company)) }      
      end
    
      companies << { :name                => company.name,
                     :permalink           => company.permalink,
                     :crunchbase_url      => company.crunchbase_url,
                     :homepage_url        => company.homepage_url || "",
                     :category_code       => company.category_code || "",
                     :number_of_employees => company.number_of_employees || 0,
                     :overview            => company.overview || "",
                     :total_money_raised  => company.total_money_raised || "$0.0M"
                    }

      company.tags.each do |tag|
        tags.add({:name => tag})
        tagged << {:from  => tag,
                   :to    => company.permalink,
                   :type  => "tagged"}        
      end
      
      company.relationships.each do |employee|
        employees << {:from  => employee.person_permalink,
                      :to    => company.permalink,
                      :type  => employee.is_past? ? "worked_at" : "works_at",
                      :properties => {:title => employee.title || ""}
                    }
      end

      company.competitions.each do |competitor|
        competes << {:from  => competitor["competitor"]["permalink"],
                     :to    => company.permalink,
                     :type  => "competes_with"}
      end

      company.funding_rounds.each do |round|
        unless round["investments"].empty?
          round["investments"].each do |investment|

            unless investment["company"].nil?
              from = investment["company"]["permalink"]
              entity = "company"
            end
            
            unless investment["financial_org"].nil?
              from = investment["financial_org"]["permalink"]
              entity = "fo"
            end

            unless investment["person"].nil?
              from = investment["person"]["permalink"]
              entity = "person"
            end

            invested.add({:from  => from,
                          :to    => company.permalink,
                          :type  => "invested_in",
                          :properties => {:entity => entity}})
          end
      end
      end
      
    rescue Exception => e   
      puts e.message
    end    
  end
  
  puts "Downloading People"  
  all_people = Crunchbase::Person.all
  all_people.each do |ap|
    begin
      next unless ap.permalink
      file = "crunchbase/people/#{ap.permalink}"
      if File.exist?(file)
        person = Marshal::load(File.open(file, 'r'))
        else
        person = ap.entity
        File.open(file, 'wb') { |fp| fp.write(Marshal::dump(person)) }      
      end

      people << {:name => "#{person.first_name || ""} #{person.last_name || ""}",
                 :permalink      => person.permalink,
                 :crunchbase_url => person.crunchbase_url || "",
                 :homepage_url   => person.homepage_url || "",
                 :overview       => person.overview || ""
                 }

    rescue Exception => e   
      puts e.message
    end    

  end
  
  puts "Downloading Financial Organizations"  
  all_fos = Crunchbase::FinancialOrganization.all
  bad_fos = ["-", "--", "---", "----"]
  all_fos.each do |af|  
    begin
      next if bad_fos.include?(af.permalink)
      file = "crunchbase/organization/#{af.permalink}"
      if File.exist?(file)
        fo = Marshal::load(File.open(file, 'r'))
      else
        fo = af.entity
        File.open(file, 'wb') { |fp| fp.write(Marshal::dump(fo)) }      
      end
      
      fos << {:name           => fo.name,
              :permalink      => fo.permalink,
              :crunchbase_url => fo.crunchbase_url || "",
              :homepage_url   => fo.homepage_url || "",
              :description    => fo.description || "",
              :overview       => fo.overview || ""
              }        
              
    rescue Exception => e   
      puts e.message
    end    
              
  end        
  


  neo = Neography::Rest.new

  puts "Creating Indexes"  
  neo.create_node_index("company_index", "fulltext", "lucene")    
  neo.create_node_index("people_index", "fulltext", "lucene")    
  neo.create_node_index("fo_index", "fulltext", "lucene")    
  neo.create_node_index("tag_index", "fulltext", "lucene")    

  puts "Creating Company Nodes"
  company_nodes = {}
  companies.each_slice(100) do |slice|
    commands = []
    slice.each_with_index do |company, index|
      commands << [:create_unique_node, "company_index", "permalink", company[:permalink], company]
    end
  
    batch_results = neo.batch *commands
    batch_results.each do |result|
      company_nodes[result["body"]["data"]["permalink"]] = result["body"]["self"].split('/').last
    end
  end

  puts "Creating People Nodes"
  people_nodes = {}
  people.each_slice(100) do |slice|
    commands = []
    slice.each_with_index do |person, index|
      commands << [:create_unique_node, "people_index", "permalink", person[:permalink],person]
    end
  
    batch_results = neo.batch *commands

    batch_results.each do |result|
      people_nodes[result["body"]["data"]["permalink"]] = result["body"]["self"].split('/').last
    end
  end

  puts "Creating Financial Organization Nodes"
  fo_nodes = {}
  fos.each_slice(100) do |slice|
    commands = []
    slice.each_with_index do |fo, index|
      commands << [:create_unique_node, "fo_index", "permalink", fo[:permalink], fo]
    end
    
    batch_results = neo.batch *commands
    
    batch_results.each do |result|
      fo_nodes[result["body"]["data"]["permalink"]] = result["body"]["self"].split('/').last
    end      
  end
  
  puts "Creating Tag Nodes"  
  tag_nodes = {}
  tags.each_slice(100) do |slice|
    commands = []
    slice.each_with_index do |tag, index|
      commands << [:create_unique_node, "tag_index", "name", tag[:name], tag]
    end
  
    batch_results = neo.batch *commands

    batch_results.each do |result|
      tag_nodes[result["body"]["data"]["name"]] = result["body"]["self"].split('/').last
    end
  end
    
  tagged.each_slice(100) do |slice|
    commands = []
    slice.each do |tag|
      commands << [:create_relationship, tag[:type], tag_nodes[tag[:from]], company_nodes[tag[:to]], nil] 
    end
    batch_results = neo.batch *commands  
  end
  
  employees.each_slice(100) do |slice|
    commands = []
    slice.each do |employee|
      commands << [:create_relationship, employee[:type], people_nodes[employee[:from]], company_nodes[employee[:to]], employee[:properties]] 
    end
    batch_results = neo.batch *commands  
  end

  
  competes.each_slice(100) do |slice|
    commands = []
    slice.each do |compete|
      commands << [:create_relationship, compete[:type], company_nodes[compete[:from]], company_nodes[compete[:to]], nil] 
    end
    batch_results = neo.batch *commands  
  end

  invested.each_slice(100) do |slice|
    commands = []
    slice.each do |invest|
      case invest[:properties][:entity]
      when "people"
        commands << [:create_relationship, invest[:type], people_nodes[invest[:from]], company_nodes[invest[:to]], invest[:properties]] 
      when "company"
        commands << [:create_relationship, invest[:type], company_nodes[invest[:from]], company_nodes[invest[:to]], invest[:properties]] 
      when "fo"
        commands << [:create_relationship, invest[:type], fo_nodes[invest[:from]], company_nodes[invest[:to]], invest[:properties]] 
      end
    end
    batch_results = neo.batch *commands  
  end
end  

class NeoCrunch < Sinatra::Application
  set :haml, :format => :html5 
  set :app_file, __FILE__

  helpers do
    def link_to(url, text=url, opts={})
      attributes = ""
      opts.each { |key,value| attributes << key.to_s << "=\"" << value << "\" "}
      "<a href=\"#{url}\" #{attributes}>#{text}</a>"
    end
  end

  def node_id(node)
    case node
      when Hash
        node["self"].split('/').last
      when String
        node.split('/').last
      else
        node
    end
  end

  def get_properties(node)
    properties = "<ul>"
    node.each_pair do |key, value|
      if key == "avatar_url"
        properties << "<li><img src='#{value}'></li>"
      else
        properties << "<li><b>#{key}:</b> #{value}</li>"
      end
    end
    properties + "</ul>"
  end

  get '/resources/show' do
    content_type :json
    neo = Neography::Rest.new    

    cypher = "START me=node(#{params[:id]}) 
              MATCH me -[r?]- related
              RETURN me, r, related"

    connections = neo.execute_query(cypher)["data"]   
 
    me = connections[0][0]["data"]
    
    relationships = []
    if connections[0][1]
      connections.group_by{|group| group[1]["type"]}.each do |key,values| 
        relationships <<  {:id => key, 
                     :name => key,
                     :values => values.collect{|n| n[2]["data"].merge({:id => node_id(n[2]) }) } }
      end
    end

     relationships = [{"name" => "No Relationships","name" => "No Relationships","values" => [{"id" => "#{params[:id]}","name" => "No Relationships "}]}] if relationships.empty?

    @node = {:details_html => "<h2>#{me["name"]}</h2>\n<p class='summary'>\n#{get_properties(me)}</p>\n",
                :data => {:attributes => relationships, 
                          :name => me["name"],
                          :id => params[:id]}
              }

      @node.to_json


    end

  get '/' do
    @neoid = params["neoid"]
    haml :index
  end
  
  get '/search' do 
    content_type :json
    neo = Neography::Rest.new    

    cypher = "START me=node:company_index({query}) 
              RETURN ID(me), me.name
              ORDER BY me.name
              LIMIT 15"

    neo.execute_query(cypher, {:query => "permalink:*#{params[:term]}*" })["data"].map{|x| { label: x[1], value: x[0]}}.to_json   
  end
  
  get '/best' do
    neo = Neography::Rest.new
    cypher = "START me=node(*) 
              MATCH me -[r?]- ()
              RETURN ID(me), COUNT(r)
              ORDER BY COUNT(r) DESC
              LIMIT 20"

    neo.execute_query(cypher)["data"].to_json
  end
end