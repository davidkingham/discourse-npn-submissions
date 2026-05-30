# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnSubmissions::DraftStore do
  fab!(:user)
  fab!(:other_user, :user)

  describe "owner CRUD" do
    it "creates, lists, updates and deletes the user's own draft" do
      draft =
        described_class.create(
          user,
          submission_type: "image",
          title: "First draft",
          data: {
            "description" => "hello",
          },
        )

      expect(draft).to be_persisted
      expect(draft.status).to eq("draft")
      expect(described_class.list(user)).to include(draft)

      updated = described_class.update(user, draft.id, title: "Renamed")
      expect(updated.title).to eq("Renamed")

      described_class.destroy(user, draft.id)
      expect(DiscourseNpnSubmissions::Submission.where(id: draft.id)).to be_empty
    end

    it "supports multiple drafts per user" do
      described_class.create(user, submission_type: "image", title: "A")
      described_class.create(user, submission_type: "image", title: "B")
      expect(described_class.list(user).count).to eq(2)
    end
  end

  describe "ownership enforcement" do
    it "does not let a user update another user's draft" do
      draft = described_class.create(other_user, submission_type: "image", title: "Theirs")

      expect { described_class.update(user, draft.id, title: "Hacked") }.to raise_error(
        ActiveRecord::RecordNotFound,
      )
      expect(draft.reload.title).to eq("Theirs")
    end

    it "does not let a user delete another user's draft" do
      draft = described_class.create(other_user, submission_type: "image", title: "Theirs")

      expect { described_class.destroy(user, draft.id) }.to raise_error(
        ActiveRecord::RecordNotFound,
      )
      expect(draft.reload).to be_present
    end

    it "does not list another user's drafts" do
      described_class.create(other_user, submission_type: "image", title: "Theirs")
      expect(described_class.list(user)).to be_empty
    end
  end
end
