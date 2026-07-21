export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      announcements: {
        Row: {
          banner: string | null
          body_md: string
          created_at: string
          event_data: Json | null
          id: string
          parish_id: string
          photos: string[]
          posted_at: string | null
          posted_by: string | null
          publish_date: string | null
          status: string
          title: string
        }
        Insert: {
          banner?: string | null
          body_md?: string
          created_at?: string
          event_data?: Json | null
          id?: string
          parish_id: string
          photos?: string[]
          posted_at?: string | null
          posted_by?: string | null
          publish_date?: string | null
          status?: string
          title: string
        }
        Update: {
          banner?: string | null
          body_md?: string
          created_at?: string
          event_data?: Json | null
          id?: string
          parish_id?: string
          photos?: string[]
          posted_at?: string | null
          posted_by?: string | null
          publish_date?: string | null
          status?: string
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "announcements_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "announcements_posted_by_fkey"
            columns: ["posted_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      ask_questions: {
        Row: {
          answered_at: string | null
          answered_by: string | null
          asker_id: string
          body: string
          category: string | null
          created_at: string
          id: string
          parish_id: string
          privacy: string
          public_anonymized: boolean
          response_body: string | null
          status: string
          urgent: boolean
        }
        Insert: {
          answered_at?: string | null
          answered_by?: string | null
          asker_id: string
          body: string
          category?: string | null
          created_at?: string
          id?: string
          parish_id: string
          privacy?: string
          public_anonymized?: boolean
          response_body?: string | null
          status?: string
          urgent?: boolean
        }
        Update: {
          answered_at?: string | null
          answered_by?: string | null
          asker_id?: string
          body?: string
          category?: string | null
          created_at?: string
          id?: string
          parish_id?: string
          privacy?: string
          public_anonymized?: boolean
          response_body?: string | null
          status?: string
          urgent?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "ask_questions_answered_by_fkey"
            columns: ["answered_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ask_questions_asker_id_fkey"
            columns: ["asker_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ask_questions_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
      bible_books: {
        Row: {
          abbrev: string
          book_order: number
          id: string
          name: string
          testament: string
          version_id: string
        }
        Insert: {
          abbrev: string
          book_order: number
          id?: string
          name: string
          testament: string
          version_id: string
        }
        Update: {
          abbrev?: string
          book_order?: number
          id?: string
          name?: string
          testament?: string
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "bible_books_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "bible_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      bible_chapters: {
        Row: {
          book_id: string
          id: string
          number: number
          verse_count: number
        }
        Insert: {
          book_id: string
          id?: string
          number: number
          verse_count?: number
        }
        Update: {
          book_id?: string
          id?: string
          number?: number
          verse_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "bible_chapters_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "bible_books"
            referencedColumns: ["id"]
          },
        ]
      }
      bible_verses: {
        Row: {
          chapter_id: string
          id: string
          number: number
          search_vector: unknown
          text: string
        }
        Insert: {
          chapter_id: string
          id?: string
          number: number
          search_vector?: unknown
          text: string
        }
        Update: {
          chapter_id?: string
          id?: string
          number?: number
          search_vector?: unknown
          text?: string
        }
        Relationships: [
          {
            foreignKeyName: "bible_verses_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "bible_chapters"
            referencedColumns: ["id"]
          },
        ]
      }
      bible_versions: {
        Row: {
          code: string
          created_at: string
          id: string
          language: string
          license: string | null
          name: string
          version: string | null
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          language?: string
          license?: string | null
          name: string
          version?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          language?: string
          license?: string | null
          name?: string
          version?: string | null
        }
        Relationships: []
      }
      blocks: {
        Row: {
          blocked_id: string
          blocker_id: string
          created_at: string
        }
        Insert: {
          blocked_id: string
          blocker_id: string
          created_at?: string
        }
        Update: {
          blocked_id?: string
          blocker_id?: string
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "blocks_blocked_id_fkey"
            columns: ["blocked_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blocks_blocker_id_fkey"
            columns: ["blocker_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      bookmarks: {
        Row: {
          created_at: string
          id: string
          user_id: string
          verse_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          user_id: string
          verse_id: string
        }
        Update: {
          created_at?: string
          id?: string
          user_id?: string
          verse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "bookmarks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bookmarks_verse_id_fkey"
            columns: ["verse_id"]
            isOneToOne: false
            referencedRelation: "bible_verses"
            referencedColumns: ["id"]
          },
        ]
      }
      campuses: {
        Row: {
          allowed_email_domains: string[]
          created_at: string
          id: string
          is_primary: boolean
          name: string
          parish_id: string
          slug: string
        }
        Insert: {
          allowed_email_domains?: string[]
          created_at?: string
          id?: string
          is_primary?: boolean
          name: string
          parish_id: string
          slug: string
        }
        Update: {
          allowed_email_domains?: string[]
          created_at?: string
          id?: string
          is_primary?: boolean
          name?: string
          parish_id?: string
          slug?: string
        }
        Relationships: [
          {
            foreignKeyName: "campuses_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
      chat_members: {
        Row: {
          chat_id: string
          joined_at: string
          last_read_at: string | null
          muted: boolean
          role: string
          user_id: string
        }
        Insert: {
          chat_id: string
          joined_at?: string
          last_read_at?: string | null
          muted?: boolean
          role?: string
          user_id: string
        }
        Update: {
          chat_id?: string
          joined_at?: string
          last_read_at?: string | null
          muted?: boolean
          role?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "chat_members_chat_id_fkey"
            columns: ["chat_id"]
            isOneToOne: false
            referencedRelation: "chats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      chats: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          house_id: string | null
          id: string
          kind: string
          parish_id: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          house_id?: string | null
          id?: string
          kind: string
          parish_id: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          house_id?: string | null
          id?: string
          kind?: string
          parish_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "chats_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chats_house_id_fkey"
            columns: ["house_id"]
            isOneToOne: false
            referencedRelation: "houses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chats_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
      content_assets: {
        Row: {
          created_at: string
          devotional_id: string | null
          id: string
          kind: string
          url: string
          word_of_day_id: string | null
        }
        Insert: {
          created_at?: string
          devotional_id?: string | null
          id?: string
          kind: string
          url: string
          word_of_day_id?: string | null
        }
        Update: {
          created_at?: string
          devotional_id?: string | null
          id?: string
          kind?: string
          url?: string
          word_of_day_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "content_assets_devotional_id_fkey"
            columns: ["devotional_id"]
            isOneToOne: false
            referencedRelation: "devotionals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_assets_devotional_id_fkey"
            columns: ["devotional_id"]
            isOneToOne: false
            referencedRelation: "todays_devotional"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_assets_word_of_day_id_fkey"
            columns: ["word_of_day_id"]
            isOneToOne: false
            referencedRelation: "todays_word_of_day"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_assets_word_of_day_id_fkey"
            columns: ["word_of_day_id"]
            isOneToOne: false
            referencedRelation: "word_of_day"
            referencedColumns: ["id"]
          },
        ]
      }
      devotional_bookmarks: {
        Row: {
          created_at: string
          devotional_id: string
          id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          devotional_id: string
          id?: string
          user_id: string
        }
        Update: {
          created_at?: string
          devotional_id?: string
          id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "devotional_bookmarks_devotional_id_fkey"
            columns: ["devotional_id"]
            isOneToOne: false
            referencedRelation: "devotionals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "devotional_bookmarks_devotional_id_fkey"
            columns: ["devotional_id"]
            isOneToOne: false
            referencedRelation: "todays_devotional"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "devotional_bookmarks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      devotional_series: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          parish_id: string
          title: string
          total_days: number | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          parish_id: string
          title: string
          total_days?: number | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          parish_id?: string
          title?: string
          total_days?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "devotional_series_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "devotional_series_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
      devotionals: {
        Row: {
          audio_url: string | null
          author_id: string | null
          body_md: string
          cover_image_url: string | null
          created_at: string
          day_in_series: number | null
          id: string
          parish_id: string
          publish_date: string | null
          reading_time_minutes: number | null
          scripture_refs: string[]
          series_id: string | null
          status: string
          title: string
          updated_at: string
          video_url: string | null
        }
        Insert: {
          audio_url?: string | null
          author_id?: string | null
          body_md?: string
          cover_image_url?: string | null
          created_at?: string
          day_in_series?: number | null
          id?: string
          parish_id: string
          publish_date?: string | null
          reading_time_minutes?: number | null
          scripture_refs?: string[]
          series_id?: string | null
          status?: string
          title: string
          updated_at?: string
          video_url?: string | null
        }
        Update: {
          audio_url?: string | null
          author_id?: string | null
          body_md?: string
          cover_image_url?: string | null
          created_at?: string
          day_in_series?: number | null
          id?: string
          parish_id?: string
          publish_date?: string | null
          reading_time_minutes?: number | null
          scripture_refs?: string[]
          series_id?: string | null
          status?: string
          title?: string
          updated_at?: string
          video_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "devotionals_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "devotionals_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "devotionals_series_id_fkey"
            columns: ["series_id"]
            isOneToOne: false
            referencedRelation: "devotional_series"
            referencedColumns: ["id"]
          },
        ]
      }
      donations: {
        Row: {
          amount_kobo: number
          anonymous: boolean
          channel: string | null
          created_at: string
          currency: string
          fees_kobo: number | null
          fund_id: string | null
          id: string
          kind: string
          note: string | null
          paid_at: string | null
          parish_id: string
          paystack_reference: string | null
          recurring_id: string | null
          reference: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_kobo: number
          anonymous?: boolean
          channel?: string | null
          created_at?: string
          currency?: string
          fees_kobo?: number | null
          fund_id?: string | null
          id?: string
          kind?: string
          note?: string | null
          paid_at?: string | null
          parish_id: string
          paystack_reference?: string | null
          recurring_id?: string | null
          reference?: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_kobo?: number
          anonymous?: boolean
          channel?: string | null
          created_at?: string
          currency?: string
          fees_kobo?: number | null
          fund_id?: string | null
          id?: string
          kind?: string
          note?: string | null
          paid_at?: string | null
          parish_id?: string
          paystack_reference?: string | null
          recurring_id?: string | null
          reference?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "donations_fund_id_fkey"
            columns: ["fund_id"]
            isOneToOne: false
            referencedRelation: "giving_funds"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "donations_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "donations_recurring_id_fkey"
            columns: ["recurring_id"]
            isOneToOne: false
            referencedRelation: "giving_recurring"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "donations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      engagement_events: {
        Row: {
          created_at: string
          event_type: string
          id: string
          target_id: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          event_type: string
          id?: string
          target_id?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          event_type?: string
          id?: string
          target_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "engagement_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      fellowship_event_rsvps: {
        Row: {
          event_id: string
          response: string
          updated_at: string
          user_id: string
        }
        Insert: {
          event_id: string
          response: string
          updated_at?: string
          user_id: string
        }
        Update: {
          event_id?: string
          response?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fellowship_event_rsvps_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "fellowship_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fellowship_event_rsvps_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      fellowship_events: {
        Row: {
          author_id: string | null
          campus_id: string | null
          cover_image_url: string | null
          created_at: string
          description: string
          ends_at: string | null
          house_id: string | null
          id: string
          location: string | null
          parish_id: string
          published: boolean
          published_at: string | null
          starts_at: string
          title: string
          updated_at: string
        }
        Insert: {
          author_id?: string | null
          campus_id?: string | null
          cover_image_url?: string | null
          created_at?: string
          description?: string
          ends_at?: string | null
          house_id?: string | null
          id?: string
          location?: string | null
          parish_id: string
          published?: boolean
          published_at?: string | null
          starts_at: string
          title: string
          updated_at?: string
        }
        Update: {
          author_id?: string | null
          campus_id?: string | null
          cover_image_url?: string | null
          created_at?: string
          description?: string
          ends_at?: string | null
          house_id?: string | null
          id?: string
          location?: string | null
          parish_id?: string
          published?: boolean
          published_at?: string | null
          starts_at?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fellowship_events_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fellowship_events_campus_id_fkey"
            columns: ["campus_id"]
            isOneToOne: false
            referencedRelation: "campuses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fellowship_events_house_id_fkey"
            columns: ["house_id"]
            isOneToOne: false
            referencedRelation: "houses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fellowship_events_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
      formation_activities: {
        Row: {
          created_at: string
          id: string
          kind: string
          occurred_on: string
          parish_id: string
          target_key: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          kind: string
          occurred_on?: string
          parish_id: string
          target_key?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          kind?: string
          occurred_on?: string
          parish_id?: string
          target_key?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "formation_activities_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "formation_activities_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      formation_campaign_completions: {
        Row: {
          campaign_id: string
          completed_at: string
          note: string | null
          user_id: string
        }
        Insert: {
          campaign_id: string
          completed_at?: string
          note?: string | null
          user_id: string
        }
        Update: {
          campaign_id?: string
          completed_at?: string
          note?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "formation_campaign_completions_campaign_id_fkey"
            columns: ["campaign_id"]
            isOneToOne: false
            referencedRelation: "formation_campaigns"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "formation_campaign_completions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      formation_campaigns: {
        Row: {
          author_id: string | null
          body: string
          campus_id: string | null
          cover_image_url: string | null
          created_at: string
          ends_on: string
          house_id: string | null
          id: string
          kind: string
          parish_id: string
          published: boolean
          published_at: string | null
          scripture_ref: string | null
          starts_on: string
          title: string
          updated_at: string
        }
        Insert: {
          author_id?: string | null
          body?: string
          campus_id?: string | null
          cover_image_url?: string | null
          created_at?: string
          ends_on: string
          house_id?: string | null
          id?: string
          kind: string
          parish_id: string
          published?: boolean
          published_at?: string | null
          scripture_ref?: string | null
          starts_on: string
          title: string
          updated_at?: string
        }
        Update: {
          author_id?: string | null
          body?: string
          campus_id?: string | null
          cover_image_url?: string | null
          created_at?: string
          ends_on?: string
          house_id?: string | null
          id?: string
          kind?: string
          parish_id?: string
          published?: boolean
          published_at?: string | null
          scripture_ref?: string | null
          starts_on?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "formation_campaigns_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "formation_campaigns_campus_id_fkey"
            columns: ["campus_id"]
            isOneToOne: false
            referencedRelation: "campuses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "formation_campaigns_house_id_fkey"
            columns: ["house_id"]
            isOneToOne: false
            referencedRelation: "houses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "formation_campaigns_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
      giving_funds: {
        Row: {
          active: boolean
          created_at: string
          description: string | null
          id: string
          name: string
          parish_id: string
          slug: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          description?: string | null
          id?: string
          name: string
          parish_id: string
          slug: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          description?: string | null
          id?: string
          name?: string
          parish_id?: string
          slug?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "giving_funds_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
      giving_recurring: {
        Row: {
          amount_kobo: number
          anonymous: boolean
          cancelled_at: string | null
          created_at: string
          currency: string
          fund_id: string | null
          id: string
          interval: string
          next_payment_at: string | null
          note: string | null
          parish_id: string
          paystack_customer_code: string | null
          paystack_email_token: string | null
          paystack_plan_code: string | null
          paystack_subscription_code: string | null
          started_at: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_kobo: number
          anonymous?: boolean
          cancelled_at?: string | null
          created_at?: string
          currency?: string
          fund_id?: string | null
          id?: string
          interval: string
          next_payment_at?: string | null
          note?: string | null
          parish_id: string
          paystack_customer_code?: string | null
          paystack_email_token?: string | null
          paystack_plan_code?: string | null
          paystack_subscription_code?: string | null
          started_at?: string | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_kobo?: number
          anonymous?: boolean
          cancelled_at?: string | null
          created_at?: string
          currency?: string
          fund_id?: string | null
          id?: string
          interval?: string
          next_payment_at?: string | null
          note?: string | null
          parish_id?: string
          paystack_customer_code?: string | null
          paystack_email_token?: string | null
          paystack_plan_code?: string | null
          paystack_subscription_code?: string | null
          started_at?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "giving_recurring_fund_id_fkey"
            columns: ["fund_id"]
            isOneToOne: false
            referencedRelation: "giving_funds"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "giving_recurring_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "giving_recurring_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      highlights: {
        Row: {
          color: string
          created_at: string
          id: string
          note_id: string | null
          user_id: string
          verse_id: string
        }
        Insert: {
          color?: string
          created_at?: string
          id?: string
          note_id?: string | null
          user_id: string
          verse_id: string
        }
        Update: {
          color?: string
          created_at?: string
          id?: string
          note_id?: string | null
          user_id?: string
          verse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "highlights_note_id_fkey"
            columns: ["note_id"]
            isOneToOne: false
            referencedRelation: "notes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "highlights_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "highlights_verse_id_fkey"
            columns: ["verse_id"]
            isOneToOne: false
            referencedRelation: "bible_verses"
            referencedColumns: ["id"]
          },
        ]
      }
      houses: {
        Row: {
          archived_at: string | null
          campus_id: string | null
          color: string
          created_at: string
          id: string
          leader_id: string | null
          name: string
          parish_id: string
          slug: string
          verse: string | null
          verse_ref: string | null
        }
        Insert: {
          archived_at?: string | null
          campus_id?: string | null
          color: string
          created_at?: string
          id?: string
          leader_id?: string | null
          name: string
          parish_id: string
          slug: string
          verse?: string | null
          verse_ref?: string | null
        }
        Update: {
          archived_at?: string | null
          campus_id?: string | null
          color?: string
          created_at?: string
          id?: string
          leader_id?: string | null
          name?: string
          parish_id?: string
          slug?: string
          verse?: string | null
          verse_ref?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "houses_campus_id_fkey"
            columns: ["campus_id"]
            isOneToOne: false
            referencedRelation: "campuses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "houses_leader_id_fkey"
            columns: ["leader_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "houses_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
      library_items: {
        Row: {
          author: string | null
          author_id: string | null
          category: string | null
          cover_image_url: string | null
          created_at: string
          description: string | null
          duration_seconds: number | null
          external_url: string | null
          file_url: string | null
          id: string
          kind: string
          parish_id: string
          published: boolean
          published_at: string | null
          title: string
          updated_at: string
        }
        Insert: {
          author?: string | null
          author_id?: string | null
          category?: string | null
          cover_image_url?: string | null
          created_at?: string
          description?: string | null
          duration_seconds?: number | null
          external_url?: string | null
          file_url?: string | null
          id?: string
          kind: string
          parish_id: string
          published?: boolean
          published_at?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          author?: string | null
          author_id?: string | null
          category?: string | null
          cover_image_url?: string | null
          created_at?: string
          description?: string | null
          duration_seconds?: number | null
          external_url?: string | null
          file_url?: string | null
          id?: string
          kind?: string
          parish_id?: string
          published?: boolean
          published_at?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "library_items_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "library_items_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
      member_deletions: {
        Row: {
          actor_name: string
          actor_profile_id: string | null
          deleted_at: string
          id: string
          parish_id: string
          target_email: string | null
          target_name: string
          target_role: string
        }
        Insert: {
          actor_name: string
          actor_profile_id?: string | null
          deleted_at?: string
          id?: string
          parish_id: string
          target_email?: string | null
          target_name: string
          target_role: string
        }
        Update: {
          actor_name?: string
          actor_profile_id?: string | null
          deleted_at?: string
          id?: string
          parish_id?: string
          target_email?: string | null
          target_name?: string
          target_role?: string
        }
        Relationships: [
          {
            foreignKeyName: "member_deletions_actor_profile_id_fkey"
            columns: ["actor_profile_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_deletions_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
      message_reactions: {
        Row: {
          created_at: string
          emoji: string
          message_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          emoji: string
          message_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          emoji?: string
          message_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "message_reactions_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_reactions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      messages: {
        Row: {
          author_id: string | null
          body: string | null
          chat_id: string
          created_at: string
          deleted_at: string | null
          edited_at: string | null
          id: string
          image_url: string | null
          kind: string
          reply_to_id: string | null
          voice_url: string | null
        }
        Insert: {
          author_id?: string | null
          body?: string | null
          chat_id: string
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          image_url?: string | null
          kind?: string
          reply_to_id?: string | null
          voice_url?: string | null
        }
        Update: {
          author_id?: string | null
          body?: string | null
          chat_id?: string
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          image_url?: string | null
          kind?: string
          reply_to_id?: string | null
          voice_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "messages_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_chat_id_fkey"
            columns: ["chat_id"]
            isOneToOne: false
            referencedRelation: "chats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_reply_to_id_fkey"
            columns: ["reply_to_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
        ]
      }
      moderation_log: {
        Row: {
          action_taken: string
          created_at: string
          flag: string
          id: string
          message_id: string | null
          severity: string
        }
        Insert: {
          action_taken?: string
          created_at?: string
          flag: string
          id?: string
          message_id?: string | null
          severity?: string
        }
        Update: {
          action_taken?: string
          created_at?: string
          flag?: string
          id?: string
          message_id?: string | null
          severity?: string
        }
        Relationships: [
          {
            foreignKeyName: "moderation_log_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
        ]
      }
      notes: {
        Row: {
          body: string
          created_at: string
          id: string
          updated_at: string
          user_id: string
          verse_id: string | null
        }
        Insert: {
          body?: string
          created_at?: string
          id?: string
          updated_at?: string
          user_id: string
          verse_id?: string | null
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          updated_at?: string
          user_id?: string
          verse_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notes_verse_id_fkey"
            columns: ["verse_id"]
            isOneToOne: false
            referencedRelation: "bible_verses"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          channel: string
          enabled: boolean
          type: string
          user_id: string
        }
        Insert: {
          channel: string
          enabled?: boolean
          type: string
          user_id: string
        }
        Update: {
          channel?: string
          enabled?: boolean
          type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_preferences_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          created_at: string
          id: string
          preview: string | null
          read_at: string | null
          target_id: string | null
          target_url: string | null
          title: string
          type: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          preview?: string | null
          read_at?: string | null
          target_id?: string | null
          target_url?: string | null
          title: string
          type: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          preview?: string | null
          read_at?: string | null
          target_id?: string | null
          target_url?: string | null
          title?: string
          type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      parishes: {
        Row: {
          abbr: string
          campus_name: string | null
          created_at: string
          id: string
          name: string
          network_id: string | null
          slug: string
        }
        Insert: {
          abbr: string
          campus_name?: string | null
          created_at?: string
          id?: string
          name: string
          network_id?: string | null
          slug: string
        }
        Update: {
          abbr?: string
          campus_name?: string | null
          created_at?: string
          id?: string
          name?: string
          network_id?: string | null
          slug?: string
        }
        Relationships: []
      }
      paystack_events: {
        Row: {
          created_at: string
          error: string | null
          event_type: string
          id: string
          payload: Json
          paystack_id: string | null
          processed: boolean
          processed_at: string | null
          reference: string | null
          signature_valid: boolean
        }
        Insert: {
          created_at?: string
          error?: string | null
          event_type: string
          id?: string
          payload: Json
          paystack_id?: string | null
          processed?: boolean
          processed_at?: string | null
          reference?: string | null
          signature_valid?: boolean
        }
        Update: {
          created_at?: string
          error?: string | null
          event_type?: string
          id?: string
          payload?: Json
          paystack_id?: string | null
          processed?: boolean
          processed_at?: string | null
          reference?: string | null
          signature_valid?: boolean
        }
        Relationships: []
      }
      pinned_messages: {
        Row: {
          chat_id: string
          message_id: string
          pinned_at: string
          pinned_by: string | null
        }
        Insert: {
          chat_id: string
          message_id: string
          pinned_at?: string
          pinned_by?: string | null
        }
        Update: {
          chat_id?: string
          message_id?: string
          pinned_at?: string
          pinned_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pinned_messages_chat_id_fkey"
            columns: ["chat_id"]
            isOneToOne: false
            referencedRelation: "chats"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pinned_messages_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pinned_messages_pinned_by_fkey"
            columns: ["pinned_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      prayer_pray: {
        Row: {
          created_at: string
          request_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          request_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          request_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "prayer_pray_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "prayer_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prayer_pray_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      prayer_reactions: {
        Row: {
          created_at: string
          emoji: string
          request_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          emoji: string
          request_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          emoji?: string
          request_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "prayer_reactions_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "prayer_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prayer_reactions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      prayer_requests: {
        Row: {
          anonymous: boolean
          answer_note: string | null
          answered_at: string | null
          archived_at: string | null
          author_id: string
          body: string
          created_at: string
          house_id: string | null
          id: string
          parish_id: string
          praise: boolean
          urgent: boolean
        }
        Insert: {
          anonymous?: boolean
          answer_note?: string | null
          answered_at?: string | null
          archived_at?: string | null
          author_id: string
          body: string
          created_at?: string
          house_id?: string | null
          id?: string
          parish_id: string
          praise?: boolean
          urgent?: boolean
        }
        Update: {
          anonymous?: boolean
          answer_note?: string | null
          answered_at?: string | null
          archived_at?: string | null
          author_id?: string
          body?: string
          created_at?: string
          house_id?: string | null
          id?: string
          parish_id?: string
          praise?: boolean
          urgent?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "prayer_requests_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prayer_requests_house_id_fkey"
            columns: ["house_id"]
            isOneToOne: false
            referencedRelation: "houses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "prayer_requests_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
      push_tokens: {
        Row: {
          created_at: string
          expo_token: string
          id: string
          platform: string
          user_id: string
        }
        Insert: {
          created_at?: string
          expo_token: string
          id?: string
          platform: string
          user_id: string
        }
        Update: {
          created_at?: string
          expo_token?: string
          id?: string
          platform?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "push_tokens_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      reading_plan_days: {
        Row: {
          audio_url: string | null
          created_at: string
          day_number: number
          devotional_id: string | null
          id: string
          plan_id: string
          reflection_body: string
          reflection_prompt: string
          scripture_reference: string
          scripture_text: string | null
          title: string
        }
        Insert: {
          audio_url?: string | null
          created_at?: string
          day_number: number
          devotional_id?: string | null
          id?: string
          plan_id: string
          reflection_body: string
          reflection_prompt: string
          scripture_reference: string
          scripture_text?: string | null
          title: string
        }
        Update: {
          audio_url?: string | null
          created_at?: string
          day_number?: number
          devotional_id?: string | null
          id?: string
          plan_id?: string
          reflection_body?: string
          reflection_prompt?: string
          scripture_reference?: string
          scripture_text?: string | null
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "reading_plan_days_devotional_id_fkey"
            columns: ["devotional_id"]
            isOneToOne: false
            referencedRelation: "devotionals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_plan_days_devotional_id_fkey"
            columns: ["devotional_id"]
            isOneToOne: false
            referencedRelation: "todays_devotional"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_plan_days_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "reading_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      reading_plan_progress: {
        Row: {
          completed_at: string
          created_at: string
          day_id: string
          id: string
          reflection_response: string | null
          share_with_discipler: boolean
          subscription_id: string
        }
        Insert: {
          completed_at?: string
          created_at?: string
          day_id: string
          id?: string
          reflection_response?: string | null
          share_with_discipler?: boolean
          subscription_id: string
        }
        Update: {
          completed_at?: string
          created_at?: string
          day_id?: string
          id?: string
          reflection_response?: string | null
          share_with_discipler?: boolean
          subscription_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reading_plan_progress_day_id_fkey"
            columns: ["day_id"]
            isOneToOne: false
            referencedRelation: "reading_plan_days"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_plan_progress_subscription_id_fkey"
            columns: ["subscription_id"]
            isOneToOne: false
            referencedRelation: "reading_plan_subscriptions"
            referencedColumns: ["id"]
          },
        ]
      }
      reading_plan_subscriptions: {
        Row: {
          completed_at: string | null
          created_at: string
          current_day: number
          id: string
          last_activity_at: string
          paused: boolean
          plan_id: string
          started_at: string
          streak_enabled: boolean
          user_id: string
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          current_day?: number
          id?: string
          last_activity_at?: string
          paused?: boolean
          plan_id: string
          started_at?: string
          streak_enabled?: boolean
          user_id: string
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          current_day?: number
          id?: string
          last_activity_at?: string
          paused?: boolean
          plan_id?: string
          started_at?: string
          streak_enabled?: boolean
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reading_plan_subscriptions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "reading_plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_plan_subscriptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      reading_plans: {
        Row: {
          author_id: string | null
          cover_image_url: string | null
          created_at: string
          description: string
          difficulty: string | null
          id: string
          length_days: number
          parish_id: string
          published: boolean
          published_at: string | null
          sequence_locked: boolean
          slug: string
          title: string
          updated_at: string
        }
        Insert: {
          author_id?: string | null
          cover_image_url?: string | null
          created_at?: string
          description: string
          difficulty?: string | null
          id?: string
          length_days: number
          parish_id: string
          published?: boolean
          published_at?: string | null
          sequence_locked?: boolean
          slug: string
          title: string
          updated_at?: string
        }
        Update: {
          author_id?: string | null
          cover_image_url?: string | null
          created_at?: string
          description?: string
          difficulty?: string | null
          id?: string
          length_days?: number
          parish_id?: string
          published?: boolean
          published_at?: string | null
          sequence_locked?: boolean
          slug?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "reading_plans_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_plans_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
      reading_position: {
        Row: {
          book_id: string | null
          chapter_number: number | null
          updated_at: string
          user_id: string
          verse_number: number | null
          version_id: string | null
        }
        Insert: {
          book_id?: string | null
          chapter_number?: number | null
          updated_at?: string
          user_id: string
          verse_number?: number | null
          version_id?: string | null
        }
        Update: {
          book_id?: string | null
          chapter_number?: number | null
          updated_at?: string
          user_id?: string
          verse_number?: number | null
          version_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "reading_position_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "bible_books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_position_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_position_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "bible_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      reports: {
        Row: {
          created_at: string
          id: string
          parish_id: string
          reason: string | null
          reporter_id: string
          resolved_at: string | null
          resolved_by: string | null
          status: string
          target_id: string
          target_type: string
        }
        Insert: {
          created_at?: string
          id?: string
          parish_id: string
          reason?: string | null
          reporter_id: string
          resolved_at?: string | null
          resolved_by?: string | null
          status?: string
          target_id: string
          target_type: string
        }
        Update: {
          created_at?: string
          id?: string
          parish_id?: string
          reason?: string | null
          reporter_id?: string
          resolved_at?: string | null
          resolved_by?: string | null
          status?: string
          target_id?: string
          target_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "reports_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_reporter_id_fkey"
            columns: ["reporter_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      scripture_collection_verses: {
        Row: {
          collection_id: string
          created_at: string
          verse_id: string
        }
        Insert: {
          collection_id: string
          created_at?: string
          verse_id: string
        }
        Update: {
          collection_id?: string
          created_at?: string
          verse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "scripture_collection_verses_collection_id_fkey"
            columns: ["collection_id"]
            isOneToOne: false
            referencedRelation: "scripture_collections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scripture_collection_verses_verse_id_fkey"
            columns: ["verse_id"]
            isOneToOne: false
            referencedRelation: "bible_verses"
            referencedColumns: ["id"]
          },
        ]
      }
      scripture_collections: {
        Row: {
          color: string
          created_at: string
          id: string
          title: string
          updated_at: string
          user_id: string
        }
        Insert: {
          color?: string
          created_at?: string
          id?: string
          title: string
          updated_at?: string
          user_id: string
        }
        Update: {
          color?: string
          created_at?: string
          id?: string
          title?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "scripture_collections_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      streaks: {
        Row: {
          current_count: number
          grace_used_this_month: number
          last_check_in: string | null
          longest: number
          updated_at: string
          user_id: string
        }
        Insert: {
          current_count?: number
          grace_used_this_month?: number
          last_check_in?: string | null
          longest?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          current_count?: number
          grace_used_this_month?: number
          last_check_in?: string | null
          longest?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "streaks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_privacy: {
        Row: {
          cross_gender_dm_approval: boolean
          dm_who: string
          mentions_notify: boolean
          user_id: string
        }
        Insert: {
          cross_gender_dm_approval?: boolean
          dm_who?: string
          mentions_notify?: boolean
          user_id: string
        }
        Update: {
          cross_gender_dm_approval?: boolean
          dm_who?: string
          mentions_notify?: boolean
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_privacy_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_profiles: {
        Row: {
          auth_id: string
          campus_id: string | null
          date_of_birth: string | null
          dept: string | null
          discipler_id: string | null
          gender: string | null
          house_id: string | null
          id: string
          is_owner: boolean
          joined_at: string
          name: string
          parish_id: string | null
          phone: string | null
          photo_url: string | null
          photo_visibility: string
          pinned_verse_ref: string | null
          role: string
          status: string
          year: string | null
        }
        Insert: {
          auth_id: string
          campus_id?: string | null
          date_of_birth?: string | null
          dept?: string | null
          discipler_id?: string | null
          gender?: string | null
          house_id?: string | null
          id?: string
          is_owner?: boolean
          joined_at?: string
          name: string
          parish_id?: string | null
          phone?: string | null
          photo_url?: string | null
          photo_visibility?: string
          pinned_verse_ref?: string | null
          role?: string
          status?: string
          year?: string | null
        }
        Update: {
          auth_id?: string
          campus_id?: string | null
          date_of_birth?: string | null
          dept?: string | null
          discipler_id?: string | null
          gender?: string | null
          house_id?: string | null
          id?: string
          is_owner?: boolean
          joined_at?: string
          name?: string
          parish_id?: string | null
          phone?: string | null
          photo_url?: string | null
          photo_visibility?: string
          pinned_verse_ref?: string | null
          role?: string
          status?: string
          year?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "user_profiles_campus_id_fkey"
            columns: ["campus_id"]
            isOneToOne: false
            referencedRelation: "campuses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_profiles_discipler_id_fkey"
            columns: ["discipler_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_profiles_house_id_fkey"
            columns: ["house_id"]
            isOneToOne: false
            referencedRelation: "houses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_profiles_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
      verse_images: {
        Row: {
          aspect_ratio: string
          created_at: string
          id: string
          theme: string
          url: string
          user_id: string
          verse_ref: string
          verse_text: string
          watermark: boolean
        }
        Insert: {
          aspect_ratio?: string
          created_at?: string
          id?: string
          theme?: string
          url: string
          user_id: string
          verse_ref: string
          verse_text: string
          watermark?: boolean
        }
        Update: {
          aspect_ratio?: string
          created_at?: string
          id?: string
          theme?: string
          url?: string
          user_id?: string
          verse_ref?: string
          verse_text?: string
          watermark?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "verse_images_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      word_notes: {
        Row: {
          body: string
          created_at: string
          id: string
          updated_at: string
          user_id: string
          word_of_day_id: string
        }
        Insert: {
          body?: string
          created_at?: string
          id?: string
          updated_at?: string
          user_id: string
          word_of_day_id: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          updated_at?: string
          user_id?: string
          word_of_day_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "word_notes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "word_notes_word_of_day_id_fkey"
            columns: ["word_of_day_id"]
            isOneToOne: false
            referencedRelation: "todays_word_of_day"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "word_notes_word_of_day_id_fkey"
            columns: ["word_of_day_id"]
            isOneToOne: false
            referencedRelation: "word_of_day"
            referencedColumns: ["id"]
          },
        ]
      }
      word_of_day: {
        Row: {
          author_id: string | null
          cover_image_url: string | null
          created_at: string
          id: string
          parish_id: string
          prayer_md: string | null
          prompt: string | null
          publish_date: string | null
          reflection_md: string | null
          status: string
          verse_ref: string
          verse_text: string
        }
        Insert: {
          author_id?: string | null
          cover_image_url?: string | null
          created_at?: string
          id?: string
          parish_id: string
          prayer_md?: string | null
          prompt?: string | null
          publish_date?: string | null
          reflection_md?: string | null
          status?: string
          verse_ref: string
          verse_text: string
        }
        Update: {
          author_id?: string | null
          cover_image_url?: string | null
          created_at?: string
          id?: string
          parish_id?: string
          prayer_md?: string | null
          prompt?: string | null
          publish_date?: string | null
          reflection_md?: string | null
          status?: string
          verse_ref?: string
          verse_text?: string
        }
        Relationships: [
          {
            foreignKeyName: "word_of_day_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "word_of_day_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      public_qa: {
        Row: {
          answer: string | null
          answered_at: string | null
          category: string | null
          id: string | null
          parish_id: string | null
          question: string | null
        }
        Insert: {
          answer?: string | null
          answered_at?: string | null
          category?: string | null
          id?: string | null
          parish_id?: string | null
          question?: string | null
        }
        Update: {
          answer?: string | null
          answered_at?: string | null
          category?: string | null
          id?: string | null
          parish_id?: string | null
          question?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ask_questions_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
      todays_devotional: {
        Row: {
          audio_url: string | null
          author_id: string | null
          body_md: string | null
          created_at: string | null
          day_in_series: number | null
          id: string | null
          parish_id: string | null
          publish_date: string | null
          reading_time_minutes: number | null
          scripture_refs: string[] | null
          series_id: string | null
          status: string | null
          title: string | null
          updated_at: string | null
          video_url: string | null
        }
        Insert: {
          audio_url?: string | null
          author_id?: string | null
          body_md?: string | null
          created_at?: string | null
          day_in_series?: number | null
          id?: string | null
          parish_id?: string | null
          publish_date?: string | null
          reading_time_minutes?: number | null
          scripture_refs?: string[] | null
          series_id?: string | null
          status?: string | null
          title?: string | null
          updated_at?: string | null
          video_url?: string | null
        }
        Update: {
          audio_url?: string | null
          author_id?: string | null
          body_md?: string | null
          created_at?: string | null
          day_in_series?: number | null
          id?: string | null
          parish_id?: string | null
          publish_date?: string | null
          reading_time_minutes?: number | null
          scripture_refs?: string[] | null
          series_id?: string | null
          status?: string | null
          title?: string | null
          updated_at?: string | null
          video_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "devotionals_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "devotionals_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "devotionals_series_id_fkey"
            columns: ["series_id"]
            isOneToOne: false
            referencedRelation: "devotional_series"
            referencedColumns: ["id"]
          },
        ]
      }
      todays_word_of_day: {
        Row: {
          author_id: string | null
          created_at: string | null
          id: string | null
          parish_id: string | null
          prayer_md: string | null
          prompt: string | null
          publish_date: string | null
          reflection_md: string | null
          status: string | null
          verse_ref: string | null
          verse_text: string | null
        }
        Insert: {
          author_id?: string | null
          created_at?: string | null
          id?: string | null
          parish_id?: string | null
          prayer_md?: string | null
          prompt?: string | null
          publish_date?: string | null
          reflection_md?: string | null
          status?: string | null
          verse_ref?: string | null
          verse_text?: string | null
        }
        Update: {
          author_id?: string | null
          created_at?: string | null
          id?: string | null
          parish_id?: string | null
          prayer_md?: string | null
          prompt?: string | null
          publish_date?: string | null
          reflection_md?: string | null
          status?: string | null
          verse_ref?: string | null
          verse_text?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "word_of_day_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "word_of_day_parish_id_fkey"
            columns: ["parish_id"]
            isOneToOne: false
            referencedRelation: "parishes"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      answer_question: {
        Args: { p_id: string; p_public?: boolean; p_response: string }
        Returns: {
          answered_at: string | null
          answered_by: string | null
          asker_id: string
          body: string
          category: string | null
          created_at: string
          id: string
          parish_id: string
          privacy: string
          public_anonymized: boolean
          response_body: string | null
          status: string
          urgent: boolean
        }
        SetofOptions: {
          from: "*"
          to: "ask_questions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      approve_member: {
        Args: { p_campus: string; p_user: string }
        Returns: undefined
      }
      can_post_chat: { Args: { p_chat: string }; Returns: boolean }
      can_read_chat: { Args: { p_chat: string }; Returns: boolean }
      can_read_fellowship_event: { Args: { p_event: string }; Returns: boolean }
      can_read_formation_campaign: {
        Args: { p_campaign: string }
        Returns: boolean
      }
      can_read_prayer: { Args: { p_request: string }; Returns: boolean }
      complete_plan_day: {
        Args: {
          p_day_id: string
          p_reflection_response?: string
          p_share_with_discipler?: boolean
        }
        Returns: string
      }
      create_dm: { Args: { p_other: string }; Returns: string }
      create_notification: {
        Args: {
          p_preview?: string
          p_target_id?: string
          p_target_url?: string
          p_title: string
          p_type: string
          p_user: string
        }
        Returns: undefined
      }
      current_house_id: { Args: never; Returns: string }
      current_parish_id: { Args: never; Returns: string }
      current_profile_id: { Args: never; Returns: string }
      current_user_role: { Args: never; Returns: string }
      get_chapter: {
        Args: {
          book_abbrev: string
          chapter_number: number
          version_code: string
        }
        Returns: Json
      }
      is_active_member: { Args: never; Returns: boolean }
      is_blocked_by_me: { Args: { p_target: string }; Returns: boolean }
      is_chat_leader: { Args: { p_chat: string }; Returns: boolean }
      is_chat_member: { Args: { p_chat: string }; Returns: boolean }
      is_discipler_for_subscription: {
        Args: { p_sub: string }
        Returns: boolean
      }
      is_owner: { Args: never; Returns: boolean }
      is_parish_admin: { Args: never; Returns: boolean }
      list_pending_members: {
        Args: never
        Returns: {
          created_at: string
          email: string
          id: string
          name: string
        }[]
      }
      mark_prayer_answered: {
        Args: { p_answer_note?: string; p_request: string }
        Returns: undefined
      }
      owns_plan_subscription: { Args: { p_sub: string }; Returns: boolean }
      owns_scripture_collection: {
        Args: { p_collection: string }
        Returns: boolean
      }
      parse_reference: {
        Args: { ref: string; version_code?: string }
        Returns: {
          book_id: string
          book_name: string
          chapter: number
          verse: number
        }[]
      }
      record_check_in: {
        Args: never
        Returns: {
          current_count: number
          grace_used_this_month: number
          last_check_in: string | null
          longest: number
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "streaks"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      record_formation_activity: {
        Args: { p_kind: string; p_target_key?: string }
        Returns: undefined
      }
      reject_member: { Args: { p_user: string }; Returns: undefined }
      resolve_report: {
        Args: { p_report: string; p_status: string }
        Returns: undefined
      }
      search_bible: {
        Args: { max_results?: number; query: string; version_code?: string }
        Returns: {
          book_name: string
          chapter: number
          rank: number
          reference: string
          text: string
          verse: number
          verse_id: string
        }[]
      }
      set_my_campus: { Args: { p_campus: string }; Returns: undefined }
      subscribe_to_plan: { Args: { p_plan_id: string }; Returns: string }
      toggle_plan_pause: {
        Args: { p_subscription_id: string }
        Returns: boolean
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const


// App-level aliases appended after the official Supabase-generated schema.
// Keep this separate: `scripts/generate-types.sh` replaces database.types.ts.

export type PhotoVisibility = "parish" | "house" | "none";
export type UserRole = "member" | "house_leader" | "discipler" | "pastor" | "admin";
export type Gender = "male" | "female";
export type DmWho = "all_parish" | "house" | "discipler" | "none";
export type MembershipStatus = "pending" | "active" | "rejected" | "suspended";
export type ContentStatus = "draft" | "scheduled" | "published";
export type AssetKind = "image" | "audio";
export type Testament = "OT" | "NT";
export type PlanDifficulty = "starter" | "intermediate" | "deep";
export type GivingInterval = "weekly" | "monthly" | "quarterly" | "annually";
export type GivingRecurringStatus = "pending" | "active" | "paused" | "attention" | "cancelled";
export type DonationKind = "one_time" | "recurring";
export type DonationStatus = "pending" | "success" | "failed" | "abandoned" | "reversed";
export type LibraryItemKind = "book" | "manual" | "audio" | "video";
export type HighlightColor = "copper" | "gold" | "sage" | "oxblood" | "blue";
export type ChatKind = "house_group" | "announcements" | "ask_pastor_thread" | "discipler" | "dm" | "parish_group";
export type ChatMemberRole = "member" | "leader" | "pastor" | "discipler";
export type MessageKind = "text" | "voice" | "image" | "system" | "daily_prompt";
export type ReactionEmoji = "🙏" | "❤️" | "amen" | "🔥" | "✋";
export type AskPrivacy = "public" | "private";
export type AskStatus = "awaiting" | "answered";
export type ReportTargetType = "message" | "user" | "prayer_request" | "ask_question";
export type ReportStatus = "open" | "reviewing" | "resolved" | "dismissed";
export type ModerationSeverity = "low" | "medium" | "high";
export type ModerationAction = "logged" | "soft_deleted" | "escalated";
export type NotificationType = "message" | "announcement" | "ask_answered" | "mention" | "daily_prompt" | "streak" | "prayer" | "system";
export type NotificationChannel = "push" | "in_app";
export type PushPlatform = "ios" | "android";
export type VerseImageTheme = "minimal" | "organic" | "bold";
export type VerseImageAspect = "square" | "story";
export type AnnouncementBanner = "event" | "urgent";

export type Parish = Tables<"parishes">;
export type House = Tables<"houses">;
export type Campus = Tables<"campuses">;
export type UserProfile = Tables<"user_profiles">;
export type UserPrivacy = Tables<"user_privacy">;
export type DevotionalSeries = Tables<"devotional_series">;
export type Devotional = Tables<"devotionals">;
export type DevotionalBookmark = Tables<"devotional_bookmarks">;
export type WordOfDay = Tables<"word_of_day">;
export type WordNote = Tables<"word_notes">;
export type ContentAsset = Tables<"content_assets">;
export type BibleVersion = Tables<"bible_versions">;
export type BibleBook = Tables<"bible_books">;
export type BibleChapter = Tables<"bible_chapters">;
export type BibleVerse = Tables<"bible_verses">;
export type Bookmark = Tables<"bookmarks">;
export type Highlight = Tables<"highlights">;
export type Note = Tables<"notes">;
export type ReadingPosition = Tables<"reading_position">;
export type Streak = Tables<"streaks">;
export type EngagementEvent = Tables<"engagement_events">;
export type Chat = Tables<"chats">;
export type ChatMember = Tables<"chat_members">;
export type Message = Tables<"messages">;
export type MessageReaction = Tables<"message_reactions">;
export type PinnedMessage = Tables<"pinned_messages">;
export type PrayerRequest = Tables<"prayer_requests">;
export type PrayerPray = Tables<"prayer_pray">;
export type PrayerReaction = Tables<"prayer_reactions">;
export type AskQuestion = Tables<"ask_questions">;
export type PublicQa = Database["public"]["Views"]["public_qa"]["Row"];
export type Block = Tables<"blocks">;
export type Report = Tables<"reports">;
export type ModerationLog = Tables<"moderation_log">;
export type PushToken = Tables<"push_tokens">;
export type Notification = Tables<"notifications">;
export type NotificationPreference = Tables<"notification_preferences">;
export type VerseImage = Tables<"verse_images">;
export type Announcement = Tables<"announcements">;
export type ReadingPlan = Tables<"reading_plans">;
export type ReadingPlanDay = Tables<"reading_plan_days">;
export type ReadingPlanSubscription = Tables<"reading_plan_subscriptions">;
export type ReadingPlanProgress = Tables<"reading_plan_progress">;
export type GivingFund = Tables<"giving_funds">;
export type GivingRecurring = Tables<"giving_recurring">;
export type Donation = Tables<"donations">;
export type LibraryItem = Tables<"library_items">;
export type MemberDeletion = Tables<"member_deletions">;
export type FormationActivity = Tables<"formation_activities">;
export type ScriptureCollection = Tables<"scripture_collections">;
export type ScriptureCollectionVerse = Tables<"scripture_collection_verses">;
export type FormationCampaign = Tables<"formation_campaigns">;
export type FormationCampaignCompletion = Tables<"formation_campaign_completions">;
export type FellowshipEvent = Tables<"fellowship_events">;
export type FellowshipEventRsvp = Tables<"fellowship_event_rsvps">;

export type ChapterVerse = { number: number; text: string };
export type ChapterPayload = {
  version: string;
  book: string;
  abbrev: string;
  chapter: number;
  reference: string;
  verse_count: number;
  verses: ChapterVerse[];
} | null;

export type SearchResult = {
  verse_id: string;
  reference: string;
  book_name: string;
  chapter: number;
  verse: number;
  text: string;
  rank: number;
};
