# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::WeeklyChallengeInfo do
  let(:api_url) { "https://npn.example.com/wp-json/wp/v2/pages/42" }

  before do
    SiteSetting.npn_submissions_weekly_challenge_cache_minutes = 30
    SiteSetting.npn_submissions_weekly_challenge_api_url = api_url
    described_class.clear_cache
  end

  after { described_class.clear_cache }

  def stub_json(body, status: 200)
    stub_request(:get, api_url).to_return(
      status: status,
      body: body.is_a?(String) ? body : body.to_json,
      headers: {
        "Content-Type" => "application/json",
      },
    )
  end

  describe ".current" do
    it "returns nil when no API URL is configured" do
      SiteSetting.npn_submissions_weekly_challenge_api_url = ""
      expect(described_class.current).to be_nil
    end

    it "maps the ACF-in-REST shape (acf.wc_*) and link" do
      stub_json(
        {
          link: "https://npn.example.com/current-weekly-challenge/",
          acf: {
            wc_title: "Quiet Geometry",
            wc_dates: "May 20–26, 2026",
            wc_description: "Explore shape, structure, repetition, and visual rhythm in nature.",
          },
        },
      )

      result = described_class.current
      expect(result[:title]).to eq("Quiet Geometry")
      expect(result[:dates]).to eq("May 20–26, 2026")
      expect(result[:description]).to eq(
        "Explore shape, structure, repetition, and visual rhythm in nature.",
      )
      expect(result[:url]).to eq("https://npn.example.com/current-weekly-challenge/")
    end

    it "maps a flat wc_* shape with a url field" do
      stub_json(
        {
          wc_title: "Quiet Geometry",
          wc_dates: "May 20–26, 2026",
          wc_description: "Shapes.",
          url: "https://npn.example.com/c/",
        },
      )

      result = described_class.current
      expect(result[:title]).to eq("Quiet Geometry")
      expect(result[:url]).to eq("https://npn.example.com/c/")
    end

    it "passes through an already-normalized shape" do
      stub_json(
        { title: "Quiet Geometry", dates: "May 20–26", description: "x", url: "https://e.com/c" },
      )
      expect(described_class.current[:title]).to eq("Quiet Geometry")
    end

    it "uses the first entry of a collection (array) response" do
      stub_json([{ acf: { wc_title: "First" } }, { acf: { wc_title: "Second" } }])
      expect(described_class.current[:title]).to eq("First")
    end

    it "maps the production weekly-challenge CPT shape (array + acf + link)" do
      # Mirrors GET /wp-json/wp/v2/weekly-challenge?per_page=1&orderby=date&order=desc
      stub_json(
        [
          {
            link: "https://www.naturephotographers.network/weekly-challenge/quiet-geometry/",
            acf: {
              wc_title: "Quiet Geometry",
              wc_dates: "May 20–26, 2026",
              wc_description: "Explore shape, structure, repetition, and visual rhythm in nature.",
            },
          },
        ],
      )

      result = described_class.current
      expect(result[:title]).to eq("Quiet Geometry")
      expect(result[:dates]).to eq("May 20–26, 2026")
      expect(result[:description]).to eq(
        "Explore shape, structure, repetition, and visual rhythm in nature.",
      )
      expect(result[:url]).to eq(
        "https://www.naturephotographers.network/weekly-challenge/quiet-geometry/",
      )
    end

    it "returns nil for an empty collection (no published challenge yet)" do
      stub_json([])
      expect(described_class.current).to be_nil
    end

    it "reuses the cached response without re-fetching" do
      stub = stub_json({ acf: { wc_title: "Cached" } })

      described_class.current
      described_class.current

      expect(stub).to have_been_requested.once
    end

    it "strips HTML tags and decodes entities" do
      stub_json({ acf: { wc_title: "<b>Quiet</b> &amp; Bold", wc_dates: "May&nbsp;20" } })

      result = described_class.current
      expect(result[:title]).to eq("Quiet & Bold")
      expect(result[:dates]).to eq("May 20")
    end

    it "length-caps overly long fields" do
      stub_json({ acf: { wc_title: "x" * 500 } })
      expect(described_class.current[:title].length).to be <= described_class::MAX_TITLE + 1
    end

    it "returns nil when the response has no usable title" do
      stub_json({ acf: { wc_dates: "May 20" } })
      expect(described_class.current).to be_nil
    end

    it "ignores a non-http challenge URL but keeps the rest" do
      stub_json({ acf: { wc_title: "Quiet Geometry" }, link: "javascript:alert(1)" })
      result = described_class.current
      expect(result[:title]).to eq("Quiet Geometry")
      expect(result[:url]).to be_nil
    end

    context "when the fetch fails" do
      it "falls back to the last successful fetch" do
        stub_json({ acf: { wc_title: "Good Week" } })
        expect(described_class.current[:title]).to eq("Good Week")

        # Expire only the short-lived cache entry, keeping last-known-good.
        Discourse.cache.delete(described_class::PRIMARY_KEY)
        stub_request(:get, api_url).to_return(status: 500)

        expect(described_class.current[:title]).to eq("Good Week")
      end

      it "returns nil on a failed fetch with no prior success" do
        stub_request(:get, api_url).to_return(status: 500)
        expect(described_class.current).to be_nil
      end

      it "returns nil and does not raise on malformed JSON" do
        stub_json("not valid json{", status: 200)
        expect(described_class.current).to be_nil
      end

      it "returns nil and does not raise on a connection timeout" do
        stub_request(:get, api_url).to_timeout
        expect(described_class.current).to be_nil
      end
    end
  end

  describe ".clear_cache" do
    it "forces the next call to re-fetch" do
      stub_json({ acf: { wc_title: "First" } })
      expect(described_class.current[:title]).to eq("First")

      described_class.clear_cache
      stub_request(:get, api_url).to_return(
        status: 200,
        body: { acf: { wc_title: "Second" } }.to_json,
        headers: {
          "Content-Type" => "application/json",
        },
      )

      # A fresh value (not the cached "First") proves the cache was dropped; two
      # total requests confirm the second call re-fetched rather than served cache.
      expect(described_class.current[:title]).to eq("Second")
      expect(a_request(:get, api_url)).to have_been_made.twice
    end
  end
end
