#include_related_articles
require './init'

class TestPandaArticles < APITest
  def setup
    assign_http(Config['panda']['host'])
  end

  ##
  # AS-7339 | SEO: Return related brafton articles in MIP endpoint
  #
  # Steps
  # Setup
  # 1. Verify response for consumer business doe not contain articles
  # 2. Verify response for consumer business contain articles: include_related_articles = true
  def test_articles_included_with_consumer_business_endpoint
    # Setup
    query = get_valid_article_queries.sample

    get_consumer_search_resp(query, 'los angeles, ca')
    assert_response(@response, :success)
    refute_empty(@parsed_response['SearchResult']['BusinessListings'])

    int_xxid = @parsed_response['SearchResult']['BusinessListings'].sample['Int_Xxid']

    # Step 1
    get_consumer_business_resp(int_xxid)
    assert_response(@response, :success)
    assert(@parsed_response['Business'])
    refute(@parsed_response['RelatedArticles'])

    # Step 2
    search_opts = { 'include_related_articles' => 'true' }

    get_consumer_business_resp(int_xxid, search_opts)
    assert_response(@response, :success)
    assert(@parsed_response['Business'])
    refute_empty(@parsed_response['RelatedArticles'])
    business_ahc = @parsed_response['Business']['AllHeadingCodes']

    check = []
    @parsed_response['RelatedArticles'].each do |article|
      unless business_ahc & article['CategoryList']
        check << "Business All Heading Codes: #{business_ahc} to match CategoryList: #{article['CategoryList']}"
      end
    end
    assert_empty(check)
  end
end
