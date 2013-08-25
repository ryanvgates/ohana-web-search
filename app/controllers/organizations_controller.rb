class OrganizationsController < ApplicationController
  respond_to :html, :json, :xml, :js

  # search results view
  def index

    # initialize terminology box if the keyword is a term 
    # that has a matching partial as defined in Organization.terminology
    # and app/views/component/terminology
    @terminology = Organization.terminology(params[:keyword])

    # initialize query. Content may be blank if no results were found.
    query = Organization.search(params)
    
    # Provides temporary custom CIP > OE mapping of search terms that don't return results
    # If the response content is blank (no results found) check that the keyword isn't 
    # one of the homepage terms, and if so, map to a new search that returns at least one result
    if query.content.blank?
      keyword = params[:keyword].downcase
      new_params = params.dup
      
      if keyword == 'animal welfare'
        new_params[:keyword] = 'protective services for animals'
      elsif keyword == 'building support networks'
        new_params[:keyword] = 'support groups'
      elsif keyword == 'daytime caregiving'
        new_params[:keyword] = 'day care'
      elsif keyword == 'help navigating the system'
        new_params[:keyword] = '211'
      elsif keyword == 'residential caregiving'
        new_params[:keyword] = 'palliative care'
      elsif keyword == 'help finding school'
        new_params[:keyword] = 'school enrollment and curriculum'
      elsif keyword == 'help paying for school'
        new_params[:keyword] = 'money management'
      elsif keyword == 'disaster response'
        new_params[:keyword] = "disaster preparedness"
      elsif keyword == 'immediate safety needs'
        new_params[:keyword] = 'shelter/refuge'
      elsif keyword == 'psychiatric emergencies'
        new_params[:keyword] = 'psychiatric emergency room care'
      elsif keyword == 'food benefits'
        new_params[:keyword] = 'human/social services issues'
      elsif keyword == 'food delivery'
        new_params[:keyword] = "meal sites/home-delivered meals"
      elsif keyword == 'free meals'
        new_params[:keyword] = 'food pantries'
      elsif keyword == 'help paying for food'
        new_params[:keyword] = 'money management'
      elsif keyword == 'nutrition support'
        new_params[:keyword] = 'nutrition'
      elsif keyword == 'baby supplies'
        new_params[:keyword] = "UCSF Women's Health Resource Center"
      elsif keyword == 'toys and gifts'
        new_params[:keyword] = 'Community Services Agency of Mountain View'
      elsif keyword == 'addiction & recovery'
        new_params[:keyword] = 'addictions/dependencies support groups'
      elsif keyword == 'help finding services'
        new_params[:keyword] = '211'
      elsif keyword == 'help paying for healthcare'
        new_params[:keyword] = 'health screening/diagnostic services'
      elsif keyword == 'help finding housing'
        new_params[:keyword] = 'housing counseling'
      elsif keyword == 'housing advice'
        new_params[:keyword] = 'housing counseling'
      elsif keyword == 'paying for housing'
        new_params[:keyword] = 'housing expense assistance'
      elsif keyword == 'pay for childcare'
        new_params[:keyword] = 'money management'
      elsif keyword == 'pay for food'
        new_params[:keyword] = 'money management'
      elsif keyword == 'pay for housing'
        new_params[:keyword] = 'money management'
      elsif keyword == 'pay for school'
        new_params[:keyword] = 'money management'
      elsif keyword == 'health care reform'
        new_params[:keyword] = 'health insurance information/counseling'
      elsif keyword == 'market match'
        new_params[:keyword] = "market"
      elsif keyword == "senior farmers' market nutrition program"
        new_params[:keyword] = "market"
      elsif keyword == "sfmnp"
        new_params[:keyword] = "market"
      elsif keyword == "bus passes"
        new_params[:keyword] = 'transportation passes'
      elsif keyword == "transportation to appointments"
        new_params[:keyword] = 'transportation services'
      elsif keyword == "transportation to healthcare"
        new_params[:keyword] = 'transportation services'
      elsif keyword == "transportation to school"
        new_params[:keyword] = 'transportation services'
      elsif keyword == "citizenship & immigration"
        new_params[:keyword] = 'citizenship and immigration'
      end

      query = Organization.search(new_params)
    end

    # Initialize @orgs and @pagination properties that are used in the views
    @orgs = query.content
    @pagination = query.pagination

    # Adds top-level category terms to @orgs for display on results list.
    # This will likely be refactored to use the top-level keywords when those 
    # are organized in the database using OE or equivalent.
    if @orgs.present?
      top_level_service_terms = []
      Organization.service_terms.each do |term|
        top_level_service_terms.push(term[:name]);
      end

      @orgs.each do |org|
        org.category = []
        if org.keywords.present?
          org.keywords.each do |keyword|
            org.category.push( keyword ) if top_level_service_terms.include? keyword.downcase
          end
          org.category = org.category.uniq
          org.category = org.category.sort
        end
      end
    end

    # Used in the format_summary method in the result_summary_helper
    @params = {
      :count => @pagination.items_current,
      :total_count => @pagination.items_total,
      :keyword => params[:keyword],
      :location => params[:location],
      :radius => params[:radius]
    }

    # Used for appending query parameters to result entry link in list_view
    # so that the search field retains its state when visiting a detail page.
    @query_params = {
      :keyword => params[:keyword],
      :location => params[:location],
      :page => params[:page],
      :radius => params[:radius]
    }

    respond_to do |format|
      # visit directly
      format.html # index.html.haml

      # visit via ajax
      format.json {
        with_format :html do
          @html_content = render_to_string partial: 'component/organizations/results/body'
        end
        render :json => { :content => @html_content , :action => action_name }
      }
    end

  end

  # organization details view
  def show
    # retrieve specific organization's details
    @org = Organization.get(params[:id]).content

    # sometimes nearby returns a 500 error, 
    # this checks to make sure nearby has a value before initializing map data
    if @org.coordinates.present?
      @map_data = generate_map_data(Organization.nearby(params[:id]).content)
    end

    keyword         = params[:keyword] || ''
    location        = params[:location] || ''
    radius          = params[:radius] || ''
    page            = params[:page] || ''

    @search_results_url = '/organizations?page='+page
    @search_results_url += '&keyword='+URI.escape(keyword) if keyword.present?
    @search_results_url += '&location='+URI.escape(location) if location.present?
    @search_results_url += '&radius='+radius if radius.present?
    @search_results_url += '#'+params[:id]

    respond_to do |format|
      # visit directly
      format.html #show.html.haml

      # visit via ajax
      format.json {

        with_format :html do
          @html_content = render_to_string partial: 'component/organizations/detail/body'
        end
        render :json => { :content => @html_content , :action => action_name }
      }
    end

  end

  private

  # will be used for mapping nearby locations on details map view
  def generate_map_data(data)

    # generate json for the maps in the view
    # this will be injected into a <script> element in the view
    # and then consumed by the map-manager javascript.
    # map_data parses the @org hash and retrieves all entries
    # that have coordinates, and returns that as json, otherwise map_data 
    # ends up being nil and can be checked in the view with map_data.present?
    map_data = data.reduce([]) do |result, o| 
      if o.coordinates.present?
        result << {
          'id' => o._id, 
          'name' => o.name, 
          'coordinates' => o.coordinates
        }
      end
      result
    end

    map_data.push({'count'=>map_data.length,'total'=>data.length})
    map_data = map_data.to_json.html_safe unless map_data.nil?
  end

  # from http://stackoverflow.com/questions/4810584/rails-3-how-to-render-a-partial-as-a-json-response
  # execute a block with a different format (ex: an html partial while in an ajax request)
  def with_format(format, &block)
    old_formats = formats
    self.formats = [format]
    block.call
    self.formats = old_formats
    nil
  end
end