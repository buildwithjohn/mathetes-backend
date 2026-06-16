// Mathetes database types — single source of truth for mobile + admin.
// Introspected from the merged schema (migrations 0001-0021) on the local
// full-schema DB. Regenerate authoritatively with the Supabase CLI once it
// has Docker or Management-API access:
//   supabase gen types typescript --project-id <ref> > types/database.types.ts

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export interface Database {
  public: {
    Tables: {
      announcements: {
        Row: {
          id: string;
          parish_id: string;
          title: string;
          body_md: string;
          event_data: Json | null;
          banner: string | null;
          photos: string[];
          status: string;
          publish_date: string | null;
          posted_at: string | null;
          posted_by: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          parish_id: string;
          title: string;
          body_md?: string;
          event_data?: Json | null;
          banner?: string | null;
          photos?: string[];
          status?: string;
          publish_date?: string | null;
          posted_at?: string | null;
          posted_by?: string | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          parish_id?: string;
          title?: string;
          body_md?: string;
          event_data?: Json | null;
          banner?: string | null;
          photos?: string[];
          status?: string;
          publish_date?: string | null;
          posted_at?: string | null;
          posted_by?: string | null;
          created_at?: string;
        };
        Relationships: [];
      };
      ask_questions: {
        Row: {
          id: string;
          parish_id: string;
          asker_id: string;
          body: string;
          category: string | null;
          privacy: string;
          urgent: boolean;
          status: string;
          response_body: string | null;
          answered_by: string | null;
          answered_at: string | null;
          public_anonymized: boolean;
          created_at: string;
        };
        Insert: {
          id?: string;
          parish_id: string;
          asker_id: string;
          body: string;
          category?: string | null;
          privacy?: string;
          urgent?: boolean;
          status?: string;
          response_body?: string | null;
          answered_by?: string | null;
          answered_at?: string | null;
          public_anonymized?: boolean;
          created_at?: string;
        };
        Update: {
          id?: string;
          parish_id?: string;
          asker_id?: string;
          body?: string;
          category?: string | null;
          privacy?: string;
          urgent?: boolean;
          status?: string;
          response_body?: string | null;
          answered_by?: string | null;
          answered_at?: string | null;
          public_anonymized?: boolean;
          created_at?: string;
        };
        Relationships: [];
      };
      bible_books: {
        Row: {
          id: string;
          version_id: string;
          name: string;
          abbrev: string;
          testament: string;
          book_order: number;
        };
        Insert: {
          id?: string;
          version_id: string;
          name: string;
          abbrev: string;
          testament: string;
          book_order: number;
        };
        Update: {
          id?: string;
          version_id?: string;
          name?: string;
          abbrev?: string;
          testament?: string;
          book_order?: number;
        };
        Relationships: [];
      };
      bible_chapters: {
        Row: {
          id: string;
          book_id: string;
          number: number;
          verse_count: number;
        };
        Insert: {
          id?: string;
          book_id: string;
          number: number;
          verse_count?: number;
        };
        Update: {
          id?: string;
          book_id?: string;
          number?: number;
          verse_count?: number;
        };
        Relationships: [];
      };
      bible_verses: {
        Row: {
          id: string;
          chapter_id: string;
          number: number;
          text: string;
          search_vector: unknown | null;
        };
        Insert: {
          id?: string;
          chapter_id: string;
          number: number;
          text: string;
          search_vector?: unknown | null;
        };
        Update: {
          id?: string;
          chapter_id?: string;
          number?: number;
          text?: string;
          search_vector?: unknown | null;
        };
        Relationships: [];
      };
      bible_versions: {
        Row: {
          id: string;
          code: string;
          name: string;
          language: string;
          license: string | null;
          version: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          code: string;
          name: string;
          language?: string;
          license?: string | null;
          version?: string | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          code?: string;
          name?: string;
          language?: string;
          license?: string | null;
          version?: string | null;
          created_at?: string;
        };
        Relationships: [];
      };
      blocks: {
        Row: {
          blocker_id: string;
          blocked_id: string;
          created_at: string;
        };
        Insert: {
          blocker_id: string;
          blocked_id: string;
          created_at?: string;
        };
        Update: {
          blocker_id?: string;
          blocked_id?: string;
          created_at?: string;
        };
        Relationships: [];
      };
      bookmarks: {
        Row: {
          id: string;
          user_id: string;
          verse_id: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          verse_id: string;
          created_at?: string;
        };
        Update: {
          id?: string;
          user_id?: string;
          verse_id?: string;
          created_at?: string;
        };
        Relationships: [];
      };
      campuses: {
        Row: {
          id: string;
          parish_id: string;
          slug: string;
          name: string;
          is_primary: boolean;
          created_at: string;
        };
        Insert: {
          id?: string;
          parish_id: string;
          slug: string;
          name: string;
          is_primary?: boolean;
          created_at?: string;
        };
        Update: {
          id?: string;
          parish_id?: string;
          slug?: string;
          name?: string;
          is_primary?: boolean;
          created_at?: string;
        };
        Relationships: [];
      };
      chat_members: {
        Row: {
          chat_id: string;
          user_id: string;
          role: string;
          joined_at: string;
          last_read_at: string | null;
          muted: boolean;
        };
        Insert: {
          chat_id: string;
          user_id: string;
          role?: string;
          joined_at?: string;
          last_read_at?: string | null;
          muted?: boolean;
        };
        Update: {
          chat_id?: string;
          user_id?: string;
          role?: string;
          joined_at?: string;
          last_read_at?: string | null;
          muted?: boolean;
        };
        Relationships: [];
      };
      chats: {
        Row: {
          id: string;
          kind: string;
          parish_id: string;
          house_id: string | null;
          created_by: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          kind: string;
          parish_id: string;
          house_id?: string | null;
          created_by?: string | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          kind?: string;
          parish_id?: string;
          house_id?: string | null;
          created_by?: string | null;
          created_at?: string;
        };
        Relationships: [];
      };
      content_assets: {
        Row: {
          id: string;
          devotional_id: string | null;
          word_of_day_id: string | null;
          url: string;
          kind: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          devotional_id?: string | null;
          word_of_day_id?: string | null;
          url: string;
          kind: string;
          created_at?: string;
        };
        Update: {
          id?: string;
          devotional_id?: string | null;
          word_of_day_id?: string | null;
          url?: string;
          kind?: string;
          created_at?: string;
        };
        Relationships: [];
      };
      devotional_series: {
        Row: {
          id: string;
          parish_id: string;
          title: string;
          description: string | null;
          total_days: number | null;
          created_by: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          parish_id: string;
          title: string;
          description?: string | null;
          total_days?: number | null;
          created_by?: string | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          parish_id?: string;
          title?: string;
          description?: string | null;
          total_days?: number | null;
          created_by?: string | null;
          created_at?: string;
        };
        Relationships: [];
      };
      devotionals: {
        Row: {
          id: string;
          parish_id: string;
          series_id: string | null;
          day_in_series: number | null;
          title: string;
          body_md: string;
          scripture_refs: string[];
          reading_time_minutes: number | null;
          audio_url: string | null;
          author_id: string | null;
          publish_date: string | null;
          status: string;
          created_at: string;
          updated_at: string;
          video_url: string | null;
        };
        Insert: {
          id?: string;
          parish_id: string;
          series_id?: string | null;
          day_in_series?: number | null;
          title: string;
          body_md?: string;
          scripture_refs?: string[];
          reading_time_minutes?: number | null;
          audio_url?: string | null;
          author_id?: string | null;
          publish_date?: string | null;
          status?: string;
          created_at?: string;
          updated_at?: string;
          video_url?: string | null;
        };
        Update: {
          id?: string;
          parish_id?: string;
          series_id?: string | null;
          day_in_series?: number | null;
          title?: string;
          body_md?: string;
          scripture_refs?: string[];
          reading_time_minutes?: number | null;
          audio_url?: string | null;
          author_id?: string | null;
          publish_date?: string | null;
          status?: string;
          created_at?: string;
          updated_at?: string;
          video_url?: string | null;
        };
        Relationships: [];
      };
      engagement_events: {
        Row: {
          id: string;
          user_id: string;
          event_type: string;
          target_id: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          event_type: string;
          target_id?: string | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          user_id?: string;
          event_type?: string;
          target_id?: string | null;
          created_at?: string;
        };
        Relationships: [];
      };
      highlights: {
        Row: {
          id: string;
          user_id: string;
          verse_id: string;
          color: string;
          note_id: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          verse_id: string;
          color?: string;
          note_id?: string | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          user_id?: string;
          verse_id?: string;
          color?: string;
          note_id?: string | null;
          created_at?: string;
        };
        Relationships: [];
      };
      houses: {
        Row: {
          id: string;
          parish_id: string;
          slug: string;
          name: string;
          color: string;
          verse: string | null;
          verse_ref: string | null;
          leader_id: string | null;
          created_at: string;
          campus_id: string | null;
        };
        Insert: {
          id?: string;
          parish_id: string;
          slug: string;
          name: string;
          color: string;
          verse?: string | null;
          verse_ref?: string | null;
          leader_id?: string | null;
          created_at?: string;
          campus_id?: string | null;
        };
        Update: {
          id?: string;
          parish_id?: string;
          slug?: string;
          name?: string;
          color?: string;
          verse?: string | null;
          verse_ref?: string | null;
          leader_id?: string | null;
          created_at?: string;
          campus_id?: string | null;
        };
        Relationships: [];
      };
      message_reactions: {
        Row: {
          message_id: string;
          user_id: string;
          emoji: string;
          created_at: string;
        };
        Insert: {
          message_id: string;
          user_id: string;
          emoji: string;
          created_at?: string;
        };
        Update: {
          message_id?: string;
          user_id?: string;
          emoji?: string;
          created_at?: string;
        };
        Relationships: [];
      };
      messages: {
        Row: {
          id: string;
          chat_id: string;
          author_id: string | null;
          body: string | null;
          voice_url: string | null;
          image_url: string | null;
          kind: string;
          reply_to_id: string | null;
          edited_at: string | null;
          deleted_at: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          chat_id: string;
          author_id?: string | null;
          body?: string | null;
          voice_url?: string | null;
          image_url?: string | null;
          kind?: string;
          reply_to_id?: string | null;
          edited_at?: string | null;
          deleted_at?: string | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          chat_id?: string;
          author_id?: string | null;
          body?: string | null;
          voice_url?: string | null;
          image_url?: string | null;
          kind?: string;
          reply_to_id?: string | null;
          edited_at?: string | null;
          deleted_at?: string | null;
          created_at?: string;
        };
        Relationships: [];
      };
      moderation_log: {
        Row: {
          id: string;
          message_id: string | null;
          flag: string;
          severity: string;
          action_taken: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          message_id?: string | null;
          flag: string;
          severity?: string;
          action_taken?: string;
          created_at?: string;
        };
        Update: {
          id?: string;
          message_id?: string | null;
          flag?: string;
          severity?: string;
          action_taken?: string;
          created_at?: string;
        };
        Relationships: [];
      };
      notes: {
        Row: {
          id: string;
          user_id: string;
          verse_id: string | null;
          body: string;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          verse_id?: string | null;
          body?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          user_id?: string;
          verse_id?: string | null;
          body?: string;
          created_at?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      notification_preferences: {
        Row: {
          user_id: string;
          type: string;
          channel: string;
          enabled: boolean;
        };
        Insert: {
          user_id: string;
          type: string;
          channel: string;
          enabled?: boolean;
        };
        Update: {
          user_id?: string;
          type?: string;
          channel?: string;
          enabled?: boolean;
        };
        Relationships: [];
      };
      notifications: {
        Row: {
          id: string;
          user_id: string;
          type: string;
          title: string;
          preview: string | null;
          target_id: string | null;
          target_url: string | null;
          created_at: string;
          read_at: string | null;
        };
        Insert: {
          id?: string;
          user_id: string;
          type: string;
          title: string;
          preview?: string | null;
          target_id?: string | null;
          target_url?: string | null;
          created_at?: string;
          read_at?: string | null;
        };
        Update: {
          id?: string;
          user_id?: string;
          type?: string;
          title?: string;
          preview?: string | null;
          target_id?: string | null;
          target_url?: string | null;
          created_at?: string;
          read_at?: string | null;
        };
        Relationships: [];
      };
      parishes: {
        Row: {
          id: string;
          slug: string;
          name: string;
          abbr: string;
          campus_name: string | null;
          network_id: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          slug: string;
          name: string;
          abbr: string;
          campus_name?: string | null;
          network_id?: string | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          slug?: string;
          name?: string;
          abbr?: string;
          campus_name?: string | null;
          network_id?: string | null;
          created_at?: string;
        };
        Relationships: [];
      };
      pinned_messages: {
        Row: {
          chat_id: string;
          message_id: string;
          pinned_by: string | null;
          pinned_at: string;
        };
        Insert: {
          chat_id: string;
          message_id: string;
          pinned_by?: string | null;
          pinned_at?: string;
        };
        Update: {
          chat_id?: string;
          message_id?: string;
          pinned_by?: string | null;
          pinned_at?: string;
        };
        Relationships: [];
      };
      prayer_pray: {
        Row: {
          request_id: string;
          user_id: string;
          created_at: string;
        };
        Insert: {
          request_id: string;
          user_id: string;
          created_at?: string;
        };
        Update: {
          request_id?: string;
          user_id?: string;
          created_at?: string;
        };
        Relationships: [];
      };
      prayer_reactions: {
        Row: {
          request_id: string;
          user_id: string;
          emoji: string;
          created_at: string;
        };
        Insert: {
          request_id: string;
          user_id: string;
          emoji: string;
          created_at?: string;
        };
        Update: {
          request_id?: string;
          user_id?: string;
          emoji?: string;
          created_at?: string;
        };
        Relationships: [];
      };
      prayer_requests: {
        Row: {
          id: string;
          parish_id: string;
          house_id: string | null;
          author_id: string;
          body: string;
          anonymous: boolean;
          urgent: boolean;
          praise: boolean;
          archived_at: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          parish_id: string;
          house_id?: string | null;
          author_id: string;
          body: string;
          anonymous?: boolean;
          urgent?: boolean;
          praise?: boolean;
          archived_at?: string | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          parish_id?: string;
          house_id?: string | null;
          author_id?: string;
          body?: string;
          anonymous?: boolean;
          urgent?: boolean;
          praise?: boolean;
          archived_at?: string | null;
          created_at?: string;
        };
        Relationships: [];
      };
      push_tokens: {
        Row: {
          id: string;
          user_id: string;
          expo_token: string;
          platform: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          expo_token: string;
          platform: string;
          created_at?: string;
        };
        Update: {
          id?: string;
          user_id?: string;
          expo_token?: string;
          platform?: string;
          created_at?: string;
        };
        Relationships: [];
      };
      reading_position: {
        Row: {
          user_id: string;
          version_id: string | null;
          book_id: string | null;
          chapter_number: number | null;
          verse_number: number | null;
          updated_at: string;
        };
        Insert: {
          user_id: string;
          version_id?: string | null;
          book_id?: string | null;
          chapter_number?: number | null;
          verse_number?: number | null;
          updated_at?: string;
        };
        Update: {
          user_id?: string;
          version_id?: string | null;
          book_id?: string | null;
          chapter_number?: number | null;
          verse_number?: number | null;
          updated_at?: string;
        };
        Relationships: [];
      };
      reports: {
        Row: {
          id: string;
          parish_id: string;
          reporter_id: string;
          target_type: string;
          target_id: string;
          reason: string | null;
          status: string;
          resolved_by: string | null;
          resolved_at: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          parish_id: string;
          reporter_id: string;
          target_type: string;
          target_id: string;
          reason?: string | null;
          status?: string;
          resolved_by?: string | null;
          resolved_at?: string | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          parish_id?: string;
          reporter_id?: string;
          target_type?: string;
          target_id?: string;
          reason?: string | null;
          status?: string;
          resolved_by?: string | null;
          resolved_at?: string | null;
          created_at?: string;
        };
        Relationships: [];
      };
      streaks: {
        Row: {
          user_id: string;
          current_count: number;
          longest: number;
          last_check_in: string | null;
          grace_used_this_month: number;
          updated_at: string;
        };
        Insert: {
          user_id: string;
          current_count?: number;
          longest?: number;
          last_check_in?: string | null;
          grace_used_this_month?: number;
          updated_at?: string;
        };
        Update: {
          user_id?: string;
          current_count?: number;
          longest?: number;
          last_check_in?: string | null;
          grace_used_this_month?: number;
          updated_at?: string;
        };
        Relationships: [];
      };
      user_privacy: {
        Row: {
          user_id: string;
          dm_who: string;
          cross_gender_dm_approval: boolean;
          mentions_notify: boolean;
        };
        Insert: {
          user_id: string;
          dm_who?: string;
          cross_gender_dm_approval?: boolean;
          mentions_notify?: boolean;
        };
        Update: {
          user_id?: string;
          dm_who?: string;
          cross_gender_dm_approval?: boolean;
          mentions_notify?: boolean;
        };
        Relationships: [];
      };
      user_profiles: {
        Row: {
          id: string;
          auth_id: string;
          parish_id: string | null;
          house_id: string | null;
          name: string;
          photo_url: string | null;
          photo_visibility: string;
          role: string;
          gender: string | null;
          year: string | null;
          dept: string | null;
          pinned_verse_ref: string | null;
          joined_at: string;
          discipler_id: string | null;
          campus_id: string | null;
          date_of_birth: string | null;
          phone: string | null;
        };
        Insert: {
          id?: string;
          auth_id: string;
          parish_id?: string | null;
          house_id?: string | null;
          name: string;
          photo_url?: string | null;
          photo_visibility?: string;
          role?: string;
          gender?: string | null;
          year?: string | null;
          dept?: string | null;
          pinned_verse_ref?: string | null;
          joined_at?: string;
          discipler_id?: string | null;
          campus_id?: string | null;
          date_of_birth?: string | null;
          phone?: string | null;
        };
        Update: {
          id?: string;
          auth_id?: string;
          parish_id?: string | null;
          house_id?: string | null;
          name?: string;
          photo_url?: string | null;
          photo_visibility?: string;
          role?: string;
          gender?: string | null;
          year?: string | null;
          dept?: string | null;
          pinned_verse_ref?: string | null;
          joined_at?: string;
          discipler_id?: string | null;
          campus_id?: string | null;
          date_of_birth?: string | null;
          phone?: string | null;
        };
        Relationships: [];
      };
      verse_images: {
        Row: {
          id: string;
          user_id: string;
          verse_ref: string;
          verse_text: string;
          theme: string;
          aspect_ratio: string;
          watermark: boolean;
          url: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          verse_ref: string;
          verse_text: string;
          theme?: string;
          aspect_ratio?: string;
          watermark?: boolean;
          url: string;
          created_at?: string;
        };
        Update: {
          id?: string;
          user_id?: string;
          verse_ref?: string;
          verse_text?: string;
          theme?: string;
          aspect_ratio?: string;
          watermark?: boolean;
          url?: string;
          created_at?: string;
        };
        Relationships: [];
      };
      word_of_day: {
        Row: {
          id: string;
          parish_id: string;
          verse_ref: string;
          verse_text: string;
          reflection_md: string | null;
          prompt: string | null;
          author_id: string | null;
          publish_date: string | null;
          status: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          parish_id: string;
          verse_ref: string;
          verse_text: string;
          reflection_md?: string | null;
          prompt?: string | null;
          author_id?: string | null;
          publish_date?: string | null;
          status?: string;
          created_at?: string;
        };
        Update: {
          id?: string;
          parish_id?: string;
          verse_ref?: string;
          verse_text?: string;
          reflection_md?: string | null;
          prompt?: string | null;
          author_id?: string | null;
          publish_date?: string | null;
          status?: string;
          created_at?: string;
        };
        Relationships: [];
      };
    };
    Views: {
      public_qa: {
        Row: {
          id: string | null;
          parish_id: string | null;
          category: string | null;
          question: string | null;
          answer: string | null;
          answered_at: string | null;
        };
        Insert: {
          id?: string | null;
          parish_id?: string | null;
          category?: string | null;
          question?: string | null;
          answer?: string | null;
          answered_at?: string | null;
        };
        Update: {
          id?: string | null;
          parish_id?: string | null;
          category?: string | null;
          question?: string | null;
          answer?: string | null;
          answered_at?: string | null;
        };
        Relationships: [];
      };
      todays_devotional: {
        Row: {
          id: string | null;
          parish_id: string | null;
          series_id: string | null;
          day_in_series: number | null;
          title: string | null;
          body_md: string | null;
          scripture_refs: string[] | null;
          reading_time_minutes: number | null;
          audio_url: string | null;
          author_id: string | null;
          publish_date: string | null;
          status: string | null;
          created_at: string | null;
          updated_at: string | null;
        };
        Insert: {
          id?: string | null;
          parish_id?: string | null;
          series_id?: string | null;
          day_in_series?: number | null;
          title?: string | null;
          body_md?: string | null;
          scripture_refs?: string[] | null;
          reading_time_minutes?: number | null;
          audio_url?: string | null;
          author_id?: string | null;
          publish_date?: string | null;
          status?: string | null;
          created_at?: string | null;
          updated_at?: string | null;
        };
        Update: {
          id?: string | null;
          parish_id?: string | null;
          series_id?: string | null;
          day_in_series?: number | null;
          title?: string | null;
          body_md?: string | null;
          scripture_refs?: string[] | null;
          reading_time_minutes?: number | null;
          audio_url?: string | null;
          author_id?: string | null;
          publish_date?: string | null;
          status?: string | null;
          created_at?: string | null;
          updated_at?: string | null;
        };
        Relationships: [];
      };
      todays_word_of_day: {
        Row: {
          id: string | null;
          parish_id: string | null;
          verse_ref: string | null;
          verse_text: string | null;
          reflection_md: string | null;
          prompt: string | null;
          author_id: string | null;
          publish_date: string | null;
          status: string | null;
          created_at: string | null;
        };
        Insert: {
          id?: string | null;
          parish_id?: string | null;
          verse_ref?: string | null;
          verse_text?: string | null;
          reflection_md?: string | null;
          prompt?: string | null;
          author_id?: string | null;
          publish_date?: string | null;
          status?: string | null;
          created_at?: string | null;
        };
        Update: {
          id?: string | null;
          parish_id?: string | null;
          verse_ref?: string | null;
          verse_text?: string | null;
          reflection_md?: string | null;
          prompt?: string | null;
          author_id?: string | null;
          publish_date?: string | null;
          status?: string | null;
          created_at?: string | null;
        };
        Relationships: [];
      };
    };
    Functions: {
      // Identity / RLS helpers
      current_profile_id: { Args: Record<string, never>; Returns: string };
      current_parish_id: { Args: Record<string, never>; Returns: string };
      current_house_id: { Args: Record<string, never>; Returns: string };
      current_user_role: { Args: Record<string, never>; Returns: string };
      is_parish_admin: { Args: Record<string, never>; Returns: boolean };
      is_blocked_by_me: { Args: { p_target: string }; Returns: boolean };
      is_chat_member: { Args: { p_chat: string }; Returns: boolean };
      is_chat_leader: { Args: { p_chat: string }; Returns: boolean };
      can_read_chat: { Args: { p_chat: string }; Returns: boolean };
      can_post_chat: { Args: { p_chat: string }; Returns: boolean };
      // Chat
      create_dm: { Args: { p_other: string }; Returns: string };
      // Engagement
      record_check_in: { Args: Record<string, never>; Returns: Database["public"]["Tables"]["streaks"]["Row"] };
      // Ask Pastor
      answer_question: {
        Args: { p_id: string; p_response: string; p_public?: boolean };
        Returns: Database["public"]["Tables"]["ask_questions"]["Row"];
      };
      // Bible
      get_chapter: {
        Args: { version_code: string; book_abbrev: string; chapter_number: number };
        Returns: Json;
      };
      search_bible: {
        Args: { query: string; version_code?: string; max_results?: number };
        Returns: {
          verse_id: string; reference: string; book_name: string;
          chapter: number; verse: number; text: string; rank: number;
        }[];
      };
      parse_reference: {
        Args: { ref: string; version_code?: string };
        Returns: { book_id: string; book_name: string; chapter: number; verse: number }[];
      };
    };
    Enums: { [_ in never]: never };
    CompositeTypes: { [_ in never]: never };
  };
}
