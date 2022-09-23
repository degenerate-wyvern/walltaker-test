class Link < ApplicationRecord
  belongs_to :user
  has_many :viewing_users, foreign_key: :viewing_link_id, class_name: 'User'
  has_many :past_links
  has_many :comments, dependent: :destroy
  has_many :abilities, class_name: 'LinkAbility', inverse_of: :link
  enum response_type: %i[horny came disgust]
  validates :expires, presence: true, unless: :never_expires?
  validates :theme, format: { without: /\s+/i, message: 'must be only 1 tag.' }
  validates :theme, format: { without: /\:/, message: 'must not contain filter or sort tags. (like score:>30) Use the Minimum Score setting instead.' }
  validates :min_score, comparison: { greater_than: -1, less_than: 301 }
  visitable :ahoy_visit

  scope :is_online, -> { where('last_ping > ?', Time.now - 1.minute).or(where('live_client_started_at > ?', Time.now - 7.days)) }

  def is_online?
    last_ping_online = last_ping > Time.now - 1.minute
    live_client_online = live_client_started_at && (live_client_started_at > Time.now - 7.days)
    last_ping_online || live_client_online
  end
  
  # @param ["can_show_videos"] ability
  def check_ability(ability)
    abilities.any? { |edge| edge.ability == ability }
  end

  # @return [User | nil]
  def get_set_by_user
    return User.find(self.set_by_id) if self.set_by_id
    nil unless self.set_by_id
  end

  after_update_commit do
    if blacklist_previously_changed? || terms_previously_changed? || theme_previously_changed? || response_text_previously_changed? || last_ping_user_agent_previously_changed? || live_client_started_at_previously_changed? || expires_previously_changed? || never_expires_previously_changed? || friends_only_previously_changed? || post_url_previously_changed?
      broadcast_update

      begin
        link = {}
        link[:success] = true
        link[:id] = self.id
        link[:expires] = self.expires
        link[:terms] = self.terms
        link[:blacklist] = self.blacklist
        link[:post_url] = self.post_url
        link[:post_thumbnail_url] = self.post_thumbnail_url
        link[:post_description] = self.post_description
        link[:response_type] = self.response_type
        link[:response_text] = self.response_text
        link[:set_by] = get_set_by_user&.username
        link[:updated_at] = self.updated_at
      rescue
        link = {
          success: false,
          why: 'Fetching link failed.'
        }
      end
      ActionCable.server.broadcast(
        "Link::#{id}",
        link
      )
    end
  end
end
