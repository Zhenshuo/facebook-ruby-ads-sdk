module FacebookAds
  # An ad account has many ad campaigns, ad images, and ad creatives.
  # https://developers.facebook.com/docs/marketing-api/reference/ad-account
  class AdAccount < Base
    FIELDS = %w(id account_id account_status age created_time currency name).freeze

    class << self
      def all(query = {})
        get('/me/adaccounts', query: query, objectify: true)
      end

      def find_by(conditions)
        all.detect do |object|
          conditions.all? do |key, value|
            object.send(key) == value
          end
        end
      end
    end

    # has_many campaigns

    def ad_campaigns(effective_status: ['ACTIVE'], limit: 100)
      AdCampaign.paginate("/#{id}/campaigns", query: { effective_status: effective_status, limit: limit })
    end

    def create_ad_campaign(name:, objective:, status: 'ACTIVE')
      raise Exception, "Objective must be one of: #{AdCampaign::OBJECTIVES.to_sentence}" unless AdCampaign::OBJECTIVES.include?(objective)
      raise Exception, "Status must be one of: #{AdCampaign::STATUSES.to_sentence}" unless AdCampaign::STATUSES.include?(status)
      query = { name: name, objective: objective, status: status }
      result = AdCampaign.post("/#{id}/campaigns", query: query)
      AdCampaign.find(result['id'])
    end

    def create_dynamic_ad_campaign(name:, product_catalog_id:, status: 'ACTIVE')
      raise Exception, "Status must be one of: #{AdCampaign::STATUSES.to_sentence}" unless AdCampaign::STATUSES.include?(status)
      query = { name: name, objective: 'PRODUCT_CATALOG_SALES', status: status, promoted_object: { product_catalog_id: product_catalog_id } }
      result = AdCampaign.post("/#{id}/campaigns", query: query)
      AdCampaign.find(result['id'])
    end

    # has_many ad_images

    def ad_images(hashes: nil, limit: 100)
      if !hashes.nil?
        AdImage.get("/#{id}/adimages", query: { hashes: hashes }, objectify: true)
      else
        AdImage.paginate("/#{id}/adimages", query: { limit: limit })
      end
    end

    def create_ad_images(urls)
      files = urls.map do |url|
        name, path = download(url)
        [name, File.open(path)]
      end.to_h

      response = AdImage.post("/#{id}/adimages", query: files)
      files.values.each { |file| File.delete(file.path) }
      !response['images'].nil? ? ad_images(hashes: response['images'].map { |_key, hash| hash['hash'] }) : []
    end

    # has_many ad_creatives

    def ad_creatives(limit: 100)
      AdCreative.paginate("/#{id}/adcreatives", query: { limit: limit })
    end

    def create_ad_creative(creative, carousel: true)
      carousel ? create_carousel_ad_creative(creative) : create_image_ad_creative(creative)
    end

    # has_many ad_sets

    def ad_sets(effective_status: ['ACTIVE'], limit: 100)
      AdSet.paginate("/#{id}/adsets", query: { effective_status: effective_status, limit: limit })
    end

    # has_many ads

    def ads(effective_status: ['ACTIVE'], limit: 100)
      Ad.paginate("/#{id}/ads", query: { effective_status: effective_status, limit: limit })
    end

    # has_many ad_audiences

    def ad_audiences
      AdAudience.paginate("/#{id}/customaudiences")
    end

    # has_many ad_insights

    def ad_insights(range: Date.today..Date.today, level: 'ad', time_increment: 1)
      ad_campaigns.map do |ad_campaign|
        ad_campaign.ad_insights(range: range, level: level, time_increment: time_increment)
      end.flatten
    end

    # has_many applications

    def applications
      self.class.get("/#{id}/advertisable_applications", objectify: false)
    end

    def create_ad_audience_with_pixel(name:, pixel_id:, event_name:)
      query = {
          name: name,
          pixel_id: pixel_id,
          subtype: 'WEBSITE',
          retention_days: 15,
          rule: { event: { i_contains: event_name } }.to_json,
          prefill: 1
        }
      result = AdAudience.post("/#{id}/customaudiences", query: query)
      AdAudience.find(result['id'])
    end

    def create_page_like_ad_audience(name:, ratio:, country:, page_id:)
      query = {
          name: name,
          subtype: 'LOOKALIKE',
          lookalike_spec: {
            ratio: ratio,
            country: country,
            page_id: page_id,
            conversion_type: 'page_like'
          }.to_json
      }
      result = AdAudience.post("/#{id}/customaudiences", query: query)
      AdAudience.find(result['id'])
    end

    private

    def create_carousel_ad_creative(creative)
      required = %i(name page_id link message assets call_to_action_type multi_share_optimized multi_share_end_card)
      unless (keys = required - creative.keys).length.zero?
        raise Exception, "Creative is missing the following: #{keys.to_sentence}"
      end

      raise Exception, "Creative call_to_action_type must be one of: #{AdCreative::CALL_TO_ACTION_TYPES.to_sentence}" unless AdCreative::CALL_TO_ACTION_TYPES.include?(creative[:call_to_action_type])
      query = if creative[:product_set_id].present?
        AdCreative.product_set(name: creative[:name], page_id: creative[:page_id], link: creative[:link], message: creative[:message], headline: creative[:headline], description: creative[:description], product_set_id: creative[:product_set_id])
      else
        AdCreative.carousel(creative)
      end
      result = AdCreative.post("/#{id}/adcreatives", query: query)
      AdCreative.find(result['id'])
    end

    def create_image_ad_creative(creative)
      required = %i(name page_id message link link_title description image_hash call_to_action_type)

      unless (keys = required - creative.keys).length.zero?
        raise Exception, "Creative is missing the following: #{keys.to_sentence}"
      end

      raise Exception, "Creative call_to_action_type must be one of: #{AdCreative::CALL_TO_ACTION_TYPES.to_sentence}" unless AdCreative::CALL_TO_ACTION_TYPES.include?(creative[:call_to_action_type])
      query = AdCreative.photo(creative)
      result = AdCreative.post("/#{id}/adcreatives", query: query)
      AdCreative.find(result['id'])
    end

    def download(url)
      pathname = Pathname.new(url)
      name = "#{pathname.dirname.basename}.jpg"
      # @FIXME: Need to handle exception here.
      data = RestClient.get(url).body
      file = File.open("/tmp/#{name}", 'w') # Assume *nix-based system.
      file.binmode
      file.write(data)
      file.close
      [name, file.path]
    end
  end
end
