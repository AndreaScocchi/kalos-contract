export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
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
      activities: {
        Row: {
          active_months: Json | null
          category: Database["public"]["Enums"]["activity_category"]
          color: string | null
          created_at: string | null
          default_location_id: string | null
          deleted_at: string | null
          description: string | null
          discipline: string
          duration_minutes: number | null
          group_id: string | null
          icon_name: string | null
          id: string
          image_url: string | null
          is_active: boolean | null
          journey_structure: Json | null
          landing_subtitle: string | null
          landing_title: string | null
          name: string
          program_objectives: Json | null
          slug: string | null
          target_audience: Json | null
          trial_enabled: boolean
          updated_at: string | null
          why_participate: Json | null
        }
        Insert: {
          active_months?: Json | null
          category?: Database["public"]["Enums"]["activity_category"]
          color?: string | null
          created_at?: string | null
          default_location_id?: string | null
          deleted_at?: string | null
          description?: string | null
          discipline: string
          duration_minutes?: number | null
          group_id?: string | null
          icon_name?: string | null
          id?: string
          image_url?: string | null
          is_active?: boolean | null
          journey_structure?: Json | null
          landing_subtitle?: string | null
          landing_title?: string | null
          name: string
          program_objectives?: Json | null
          slug?: string | null
          target_audience?: Json | null
          trial_enabled?: boolean
          updated_at?: string | null
          why_participate?: Json | null
        }
        Update: {
          active_months?: Json | null
          category?: Database["public"]["Enums"]["activity_category"]
          color?: string | null
          created_at?: string | null
          default_location_id?: string | null
          deleted_at?: string | null
          description?: string | null
          discipline?: string
          duration_minutes?: number | null
          group_id?: string | null
          icon_name?: string | null
          id?: string
          image_url?: string | null
          is_active?: boolean | null
          journey_structure?: Json | null
          landing_subtitle?: string | null
          landing_title?: string | null
          name?: string
          program_objectives?: Json | null
          slug?: string | null
          target_audience?: Json | null
          trial_enabled?: boolean
          updated_at?: string | null
          why_participate?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "activities_default_location_id_fkey"
            columns: ["default_location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activities_default_location_id_fkey"
            columns: ["default_location_id"]
            isOneToOne: false
            referencedRelation: "public_site_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activities_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "activity_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activities_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "public_site_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      activity_groups: {
        Row: {
          color: string | null
          created_at: string
          description: string | null
          display_order: number
          id: string
          image_url: string | null
          is_active: boolean
          name: string
          seo_description: string | null
          seo_title: string | null
          slug: string
          updated_at: string
        }
        Insert: {
          color?: string | null
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          image_url?: string | null
          is_active?: boolean
          name: string
          seo_description?: string | null
          seo_title?: string | null
          slug: string
          updated_at?: string
        }
        Update: {
          color?: string | null
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          image_url?: string | null
          is_active?: boolean
          name?: string
          seo_description?: string | null
          seo_title?: string | null
          slug?: string
          updated_at?: string
        }
        Relationships: []
      }
      announcements: {
        Row: {
          body: string
          category: string
          created_at: string
          created_by: string | null
          ends_at: string | null
          id: string
          image_url: string | null
          is_active: boolean
          is_recurring: boolean
          is_test: boolean
          last_sent_at: string | null
          link_label: string | null
          link_url: string | null
          marketing_campaign_id: string | null
          next_occurrence_at: string | null
          recurrence_day_of_month: number | null
          recurrence_day_of_week: number | null
          recurrence_frequency:
            | Database["public"]["Enums"]["announcement_recurrence_frequency"]
            | null
          recurrence_time: string | null
          starts_at: string
          test_client_id: string | null
          title: string
          updated_at: string
        }
        Insert: {
          body: string
          category?: string
          created_at?: string
          created_by?: string | null
          ends_at?: string | null
          id?: string
          image_url?: string | null
          is_active?: boolean
          is_recurring?: boolean
          is_test?: boolean
          last_sent_at?: string | null
          link_label?: string | null
          link_url?: string | null
          marketing_campaign_id?: string | null
          next_occurrence_at?: string | null
          recurrence_day_of_month?: number | null
          recurrence_day_of_week?: number | null
          recurrence_frequency?:
            | Database["public"]["Enums"]["announcement_recurrence_frequency"]
            | null
          recurrence_time?: string | null
          starts_at?: string
          test_client_id?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          body?: string
          category?: string
          created_at?: string
          created_by?: string | null
          ends_at?: string | null
          id?: string
          image_url?: string | null
          is_active?: boolean
          is_recurring?: boolean
          is_test?: boolean
          last_sent_at?: string | null
          link_label?: string | null
          link_url?: string | null
          marketing_campaign_id?: string | null
          next_occurrence_at?: string | null
          recurrence_day_of_month?: number | null
          recurrence_day_of_week?: number | null
          recurrence_frequency?:
            | Database["public"]["Enums"]["announcement_recurrence_frequency"]
            | null
          recurrence_time?: string | null
          starts_at?: string
          test_client_id?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "announcements_marketing_campaign_id_fkey"
            columns: ["marketing_campaign_id"]
            isOneToOne: false
            referencedRelation: "campaigns"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "announcements_test_client_id_fkey"
            columns: ["test_client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      association_settings: {
        Row: {
          address_city: string
          address_province: string
          address_street: string
          address_zip: string
          email: string | null
          fiscal_code: string
          id: boolean
          ledger_start_date: string
          legal_name: string
          legal_representative: string | null
          pec: string | null
          phone: string | null
          receipt_footer: string | null
          receipt_prefix: string
          runts_number: string | null
          runts_registered: boolean
          short_legal_name: string
          stamp_duty_cents: number
          stamp_duty_threshold_cents: number
          updated_at: string
          updated_by: string | null
          vat_number: string | null
        }
        Insert: {
          address_city: string
          address_province: string
          address_street: string
          address_zip: string
          email?: string | null
          fiscal_code: string
          id?: boolean
          ledger_start_date?: string
          legal_name: string
          legal_representative?: string | null
          pec?: string | null
          phone?: string | null
          receipt_footer?: string | null
          receipt_prefix?: string
          runts_number?: string | null
          runts_registered?: boolean
          short_legal_name: string
          stamp_duty_cents?: number
          stamp_duty_threshold_cents?: number
          updated_at?: string
          updated_by?: string | null
          vat_number?: string | null
        }
        Update: {
          address_city?: string
          address_province?: string
          address_street?: string
          address_zip?: string
          email?: string | null
          fiscal_code?: string
          id?: boolean
          ledger_start_date?: string
          legal_name?: string
          legal_representative?: string | null
          pec?: string | null
          phone?: string | null
          receipt_footer?: string | null
          receipt_prefix?: string
          runts_number?: string | null
          runts_registered?: boolean
          short_legal_name?: string
          stamp_duty_cents?: number
          stamp_duty_threshold_cents?: number
          updated_at?: string
          updated_by?: string | null
          vat_number?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "association_settings_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      association_years: {
        Row: {
          created_at: string
          created_by: string | null
          fee_cents: number | null
          fee_due_date: string | null
          is_open: boolean
          notes: string | null
          updated_at: string
          year: number
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          fee_cents?: number | null
          fee_due_date?: string | null
          is_open?: boolean
          notes?: string | null
          updated_at?: string
          year: number
        }
        Update: {
          created_at?: string
          created_by?: string | null
          fee_cents?: number | null
          fee_due_date?: string | null
          is_open?: boolean
          notes?: string | null
          updated_at?: string
          year?: number
        }
        Relationships: [
          {
            foreignKeyName: "association_years_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      auth_email_logs: {
        Row: {
          created_at: string
          email: string
          email_type: string
          error_message: string | null
          id: string
          metadata: Json | null
          resend_id: string | null
          source: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          email: string
          email_type: string
          error_message?: string | null
          id?: string
          metadata?: Json | null
          resend_id?: string | null
          source: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          email?: string
          email_type?: string
          error_message?: string | null
          id?: string
          metadata?: Json | null
          resend_id?: string | null
          source?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      bookings: {
        Row: {
          client_id: string | null
          created_at: string | null
          id: string
          is_trial: boolean
          lesson_id: string
          status: Database["public"]["Enums"]["booking_status"]
          subscription_id: string | null
        }
        Insert: {
          client_id?: string | null
          created_at?: string | null
          id?: string
          is_trial?: boolean
          lesson_id: string
          status?: Database["public"]["Enums"]["booking_status"]
          subscription_id?: string | null
        }
        Update: {
          client_id?: string | null
          created_at?: string | null
          id?: string
          is_trial?: boolean
          lesson_id?: string
          status?: Database["public"]["Enums"]["booking_status"]
          subscription_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "bookings_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bookings_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lesson_occupancy"
            referencedColumns: ["lesson_id"]
          },
          {
            foreignKeyName: "bookings_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lessons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bookings_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bookings_subscription_id_fkey"
            columns: ["subscription_id"]
            isOneToOne: false
            referencedRelation: "subscriptions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bookings_subscription_id_fkey"
            columns: ["subscription_id"]
            isOneToOne: false
            referencedRelation: "subscriptions_with_remaining"
            referencedColumns: ["id"]
          },
        ]
      }
      bug_reports: {
        Row: {
          created_at: string
          created_by_client_id: string | null
          created_by_user_id: string | null
          deleted_at: string | null
          description: string
          id: string
          image_url: string | null
          status: Database["public"]["Enums"]["bug_status"]
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by_client_id?: string | null
          created_by_user_id?: string | null
          deleted_at?: string | null
          description: string
          id?: string
          image_url?: string | null
          status?: Database["public"]["Enums"]["bug_status"]
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by_client_id?: string | null
          created_by_user_id?: string | null
          deleted_at?: string | null
          description?: string
          id?: string
          image_url?: string | null
          status?: Database["public"]["Enums"]["bug_status"]
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "bug_reports_created_by_client_id_fkey"
            columns: ["created_by_client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bug_reports_created_by_user_id_fkey"
            columns: ["created_by_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      bussola_requests: {
        Row: {
          client_id: string
          created_at: string
          handled_by: string | null
          id: string
          lesson_id: string | null
          metadata: Json | null
          note: string | null
          preferred_at: string | null
          status: Database["public"]["Enums"]["bussola_request_status"]
          updated_at: string
        }
        Insert: {
          client_id: string
          created_at?: string
          handled_by?: string | null
          id?: string
          lesson_id?: string | null
          metadata?: Json | null
          note?: string | null
          preferred_at?: string | null
          status?: Database["public"]["Enums"]["bussola_request_status"]
          updated_at?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          handled_by?: string | null
          id?: string
          lesson_id?: string | null
          metadata?: Json | null
          note?: string | null
          preferred_at?: string | null
          status?: Database["public"]["Enums"]["bussola_request_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "bussola_requests_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bussola_requests_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lesson_occupancy"
            referencedColumns: ["lesson_id"]
          },
          {
            foreignKeyName: "bussola_requests_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lessons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bussola_requests_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["id"]
          },
        ]
      }
      campaign_analytics: {
        Row: {
          campaign_id: string
          channel: string
          clicks: number | null
          comments: number | null
          content_id: string | null
          created_at: string
          emails_bounced: number | null
          emails_clicked: number | null
          emails_delivered: number | null
          emails_opened: number | null
          emails_sent: number | null
          engagement: number | null
          id: string
          impressions: number | null
          last_fetched_at: string | null
          likes: number | null
          push_clicked: number | null
          push_delivered: number | null
          push_sent: number | null
          reach: number | null
          saves: number | null
          shares: number | null
          story_replies: number | null
          story_views: number | null
          updated_at: string
        }
        Insert: {
          campaign_id: string
          channel: string
          clicks?: number | null
          comments?: number | null
          content_id?: string | null
          created_at?: string
          emails_bounced?: number | null
          emails_clicked?: number | null
          emails_delivered?: number | null
          emails_opened?: number | null
          emails_sent?: number | null
          engagement?: number | null
          id?: string
          impressions?: number | null
          last_fetched_at?: string | null
          likes?: number | null
          push_clicked?: number | null
          push_delivered?: number | null
          push_sent?: number | null
          reach?: number | null
          saves?: number | null
          shares?: number | null
          story_replies?: number | null
          story_views?: number | null
          updated_at?: string
        }
        Update: {
          campaign_id?: string
          channel?: string
          clicks?: number | null
          comments?: number | null
          content_id?: string | null
          created_at?: string
          emails_bounced?: number | null
          emails_clicked?: number | null
          emails_delivered?: number | null
          emails_opened?: number | null
          emails_sent?: number | null
          engagement?: number | null
          id?: string
          impressions?: number | null
          last_fetched_at?: string | null
          likes?: number | null
          push_clicked?: number | null
          push_delivered?: number | null
          push_sent?: number | null
          reach?: number | null
          saves?: number | null
          shares?: number | null
          story_replies?: number | null
          story_views?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "campaign_analytics_campaign_id_fkey"
            columns: ["campaign_id"]
            isOneToOne: false
            referencedRelation: "campaigns"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_analytics_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "campaign_contents"
            referencedColumns: ["id"]
          },
        ]
      }
      campaign_contents: {
        Row: {
          ai_generated_body: string | null
          ai_generated_hashtags: string[] | null
          ai_generated_image_suggestions: string[] | null
          ai_generated_title: string | null
          body: string | null
          campaign_id: string
          content_type: Database["public"]["Enums"]["campaign_content_type"]
          created_at: string
          error_message: string | null
          hashtags: string[] | null
          id: string
          image_suggestions: string[] | null
          image_url: string | null
          is_edited: boolean | null
          link_label: string | null
          link_url: string | null
          meta_container_id: string | null
          meta_post_id: string | null
          newsletter_campaign_id: string | null
          platform: Database["public"]["Enums"]["social_platform"] | null
          published_at: string | null
          retry_count: number | null
          scheduled_for: string | null
          scheduled_offset_days: number | null
          sent_at: string | null
          sequence_index: number | null
          slides: Json | null
          social_connection_id: string | null
          status: Database["public"]["Enums"]["content_status"]
          story_text_overlays: string[] | null
          title: string | null
          updated_at: string
          video_url: string | null
        }
        Insert: {
          ai_generated_body?: string | null
          ai_generated_hashtags?: string[] | null
          ai_generated_image_suggestions?: string[] | null
          ai_generated_title?: string | null
          body?: string | null
          campaign_id: string
          content_type: Database["public"]["Enums"]["campaign_content_type"]
          created_at?: string
          error_message?: string | null
          hashtags?: string[] | null
          id?: string
          image_suggestions?: string[] | null
          image_url?: string | null
          is_edited?: boolean | null
          link_label?: string | null
          link_url?: string | null
          meta_container_id?: string | null
          meta_post_id?: string | null
          newsletter_campaign_id?: string | null
          platform?: Database["public"]["Enums"]["social_platform"] | null
          published_at?: string | null
          retry_count?: number | null
          scheduled_for?: string | null
          scheduled_offset_days?: number | null
          sent_at?: string | null
          sequence_index?: number | null
          slides?: Json | null
          social_connection_id?: string | null
          status?: Database["public"]["Enums"]["content_status"]
          story_text_overlays?: string[] | null
          title?: string | null
          updated_at?: string
          video_url?: string | null
        }
        Update: {
          ai_generated_body?: string | null
          ai_generated_hashtags?: string[] | null
          ai_generated_image_suggestions?: string[] | null
          ai_generated_title?: string | null
          body?: string | null
          campaign_id?: string
          content_type?: Database["public"]["Enums"]["campaign_content_type"]
          created_at?: string
          error_message?: string | null
          hashtags?: string[] | null
          id?: string
          image_suggestions?: string[] | null
          image_url?: string | null
          is_edited?: boolean | null
          link_label?: string | null
          link_url?: string | null
          meta_container_id?: string | null
          meta_post_id?: string | null
          newsletter_campaign_id?: string | null
          platform?: Database["public"]["Enums"]["social_platform"] | null
          published_at?: string | null
          retry_count?: number | null
          scheduled_for?: string | null
          scheduled_offset_days?: number | null
          sent_at?: string | null
          sequence_index?: number | null
          slides?: Json | null
          social_connection_id?: string | null
          status?: Database["public"]["Enums"]["content_status"]
          story_text_overlays?: string[] | null
          title?: string | null
          updated_at?: string
          video_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "campaign_contents_campaign_id_fkey"
            columns: ["campaign_id"]
            isOneToOne: false
            referencedRelation: "campaigns"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_contents_newsletter_campaign_id_fkey"
            columns: ["newsletter_campaign_id"]
            isOneToOne: false
            referencedRelation: "newsletter_campaigns"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_contents_social_connection_id_fkey"
            columns: ["social_connection_id"]
            isOneToOne: false
            referencedRelation: "social_connections"
            referencedColumns: ["id"]
          },
        ]
      }
      campaigns: {
        Row: {
          ai_generated_at: string | null
          ai_model_used: string | null
          ai_prompt_used: string | null
          created_at: string
          created_by: string | null
          current_step: number
          deleted_at: string | null
          event_date: string | null
          executed_at: string | null
          id: string
          message: string
          name: string
          scheduled_for: string | null
          skipped_steps: number[] | null
          status: Database["public"]["Enums"]["marketing_campaign_status"]
          target: Json
          test_client_id: string | null
          tone: Database["public"]["Enums"]["campaign_tone"]
          total_engagement: number | null
          total_reach: number | null
          type: Database["public"]["Enums"]["campaign_type"]
          updated_at: string
        }
        Insert: {
          ai_generated_at?: string | null
          ai_model_used?: string | null
          ai_prompt_used?: string | null
          created_at?: string
          created_by?: string | null
          current_step?: number
          deleted_at?: string | null
          event_date?: string | null
          executed_at?: string | null
          id?: string
          message: string
          name: string
          scheduled_for?: string | null
          skipped_steps?: number[] | null
          status?: Database["public"]["Enums"]["marketing_campaign_status"]
          target?: Json
          test_client_id?: string | null
          tone?: Database["public"]["Enums"]["campaign_tone"]
          total_engagement?: number | null
          total_reach?: number | null
          type: Database["public"]["Enums"]["campaign_type"]
          updated_at?: string
        }
        Update: {
          ai_generated_at?: string | null
          ai_model_used?: string | null
          ai_prompt_used?: string | null
          created_at?: string
          created_by?: string | null
          current_step?: number
          deleted_at?: string | null
          event_date?: string | null
          executed_at?: string | null
          id?: string
          message?: string
          name?: string
          scheduled_for?: string | null
          skipped_steps?: number[] | null
          status?: Database["public"]["Enums"]["marketing_campaign_status"]
          target?: Json
          test_client_id?: string | null
          tone?: Database["public"]["Enums"]["campaign_tone"]
          total_engagement?: number | null
          total_reach?: number | null
          type?: Database["public"]["Enums"]["campaign_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "campaigns_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaigns_test_client_id_fkey"
            columns: ["test_client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      clients: {
        Row: {
          birthday: string | null
          created_at: string
          deleted_at: string | null
          email: string | null
          email_bounced: boolean | null
          email_bounced_at: string | null
          full_name: string
          id: string
          is_active: boolean
          newsletter_subscribed: boolean
          notes: string | null
          phone: string | null
          profile_id: string | null
          updated_at: string
        }
        Insert: {
          birthday?: string | null
          created_at?: string
          deleted_at?: string | null
          email?: string | null
          email_bounced?: boolean | null
          email_bounced_at?: string | null
          full_name: string
          id?: string
          is_active?: boolean
          newsletter_subscribed?: boolean
          notes?: string | null
          phone?: string | null
          profile_id?: string | null
          updated_at?: string
        }
        Update: {
          birthday?: string | null
          created_at?: string
          deleted_at?: string | null
          email?: string | null
          email_bounced?: boolean | null
          email_bounced_at?: string | null
          full_name?: string
          id?: string
          is_active?: boolean
          newsletter_subscribed?: boolean
          notes?: string | null
          phone?: string | null
          profile_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clients_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      compensation_assignments: {
        Row: {
          activity_id: string | null
          created_at: string
          created_by: string | null
          id: string
          model_id: string
          note: string | null
          operator_id: string
          updated_at: string
          valid_from: string
          valid_to: string | null
        }
        Insert: {
          activity_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          model_id: string
          note?: string | null
          operator_id: string
          updated_at?: string
          valid_from: string
          valid_to?: string | null
        }
        Update: {
          activity_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          model_id?: string
          note?: string | null
          operator_id?: string
          updated_at?: string
          valid_from?: string
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "compensation_assignments_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_assignments_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "public_site_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_assignments_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["activity_id"]
          },
          {
            foreignKeyName: "compensation_assignments_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_assignments_model_id_fkey"
            columns: ["model_id"]
            isOneToOne: false
            referencedRelation: "compensation_models"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_assignments_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "operators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_assignments_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "public_site_operators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_assignments_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["operator_id"]
          },
        ]
      }
      compensation_components: {
        Row: {
          created_at: string
          display_order: number
          id: string
          kind: Database["public"]["Enums"]["compensation_component_kind"]
          model_id: string
          note: string | null
          value_cents: number | null
          value_percent: number | null
        }
        Insert: {
          created_at?: string
          display_order?: number
          id?: string
          kind: Database["public"]["Enums"]["compensation_component_kind"]
          model_id: string
          note?: string | null
          value_cents?: number | null
          value_percent?: number | null
        }
        Update: {
          created_at?: string
          display_order?: number
          id?: string
          kind?: Database["public"]["Enums"]["compensation_component_kind"]
          model_id?: string
          note?: string | null
          value_cents?: number | null
          value_percent?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "compensation_components_model_id_fkey"
            columns: ["model_id"]
            isOneToOne: false
            referencedRelation: "compensation_models"
            referencedColumns: ["id"]
          },
        ]
      }
      compensation_entries: {
        Row: {
          amount_cents: number
          approved_at: string | null
          approved_by: string | null
          breakdown: Json
          created_at: string
          created_by: string | null
          duration_minutes: number
          event_id: string | null
          expense_id: string | null
          id: string
          lesson_id: string | null
          model_id: string | null
          note: string | null
          occurred_at: string
          operator_id: string
          paid_at: string | null
          participants: number
          period_month: string
          revenue_cents: number
          status: Database["public"]["Enums"]["compensation_entry_status"]
          updated_at: string
        }
        Insert: {
          amount_cents: number
          approved_at?: string | null
          approved_by?: string | null
          breakdown?: Json
          created_at?: string
          created_by?: string | null
          duration_minutes: number
          event_id?: string | null
          expense_id?: string | null
          id?: string
          lesson_id?: string | null
          model_id?: string | null
          note?: string | null
          occurred_at: string
          operator_id: string
          paid_at?: string | null
          participants?: number
          period_month: string
          revenue_cents?: number
          status?: Database["public"]["Enums"]["compensation_entry_status"]
          updated_at?: string
        }
        Update: {
          amount_cents?: number
          approved_at?: string | null
          approved_by?: string | null
          breakdown?: Json
          created_at?: string
          created_by?: string | null
          duration_minutes?: number
          event_id?: string | null
          expense_id?: string | null
          id?: string
          lesson_id?: string | null
          model_id?: string | null
          note?: string | null
          occurred_at?: string
          operator_id?: string
          paid_at?: string | null
          participants?: number
          period_month?: string
          revenue_cents?: number
          status?: Database["public"]["Enums"]["compensation_entry_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "compensation_entries_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_entries_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_entries_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "public_site_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_entries_expense_id_fkey"
            columns: ["expense_id"]
            isOneToOne: false
            referencedRelation: "expenses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_entries_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lesson_occupancy"
            referencedColumns: ["lesson_id"]
          },
          {
            foreignKeyName: "compensation_entries_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lessons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_entries_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_entries_model_id_fkey"
            columns: ["model_id"]
            isOneToOne: false
            referencedRelation: "compensation_models"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_entries_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "operators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_entries_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "public_site_operators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compensation_entries_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["operator_id"]
          },
        ]
      }
      compensation_models: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          is_active: boolean
          max_hourly_cents: number | null
          min_guaranteed_cents: number | null
          name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          max_hourly_cents?: number | null
          min_guaranteed_cents?: number | null
          name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          max_hourly_cents?: number | null
          min_guaranteed_cents?: number | null
          name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "compensation_models_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      compensation_tiers: {
        Row: {
          amount_cents: number
          created_at: string
          id: string
          max_participants: number | null
          min_participants: number
          model_id: string
          note: string | null
        }
        Insert: {
          amount_cents: number
          created_at?: string
          id?: string
          max_participants?: number | null
          min_participants: number
          model_id: string
          note?: string | null
        }
        Update: {
          amount_cents?: number
          created_at?: string
          id?: string
          max_participants?: number | null
          min_participants?: number
          model_id?: string
          note?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "compensation_tiers_model_id_fkey"
            columns: ["model_id"]
            isOneToOne: false
            referencedRelation: "compensation_models"
            referencedColumns: ["id"]
          },
        ]
      }
      device_tokens: {
        Row: {
          app_version: string | null
          client_id: string
          created_at: string
          device_id: string | null
          expo_push_token: string
          id: string
          is_active: boolean
          last_used_at: string
          platform: string | null
          updated_at: string
        }
        Insert: {
          app_version?: string | null
          client_id: string
          created_at?: string
          device_id?: string | null
          expo_push_token: string
          id?: string
          is_active?: boolean
          last_used_at?: string
          platform?: string | null
          updated_at?: string
        }
        Update: {
          app_version?: string | null
          client_id?: string
          created_at?: string
          device_id?: string | null
          expo_push_token?: string
          id?: string
          is_active?: boolean
          last_used_at?: string
          platform?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "device_tokens_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      event_bookings: {
        Row: {
          client_id: string | null
          created_at: string | null
          event_id: string
          id: string
          status: Database["public"]["Enums"]["booking_status"]
          updated_at: string
          user_id: string | null
        }
        Insert: {
          client_id?: string | null
          created_at?: string | null
          event_id: string
          id?: string
          status?: Database["public"]["Enums"]["booking_status"]
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          client_id?: string | null
          created_at?: string | null
          event_id?: string
          id?: string
          status?: Database["public"]["Enums"]["booking_status"]
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "event_bookings_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_bookings_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_bookings_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "public_site_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_bookings_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      event_operators: {
        Row: {
          created_at: string
          event_id: string
          id: string
          model_id: string | null
          operator_id: string
          role: string | null
        }
        Insert: {
          created_at?: string
          event_id: string
          id?: string
          model_id?: string | null
          operator_id: string
          role?: string | null
        }
        Update: {
          created_at?: string
          event_id?: string
          id?: string
          model_id?: string | null
          operator_id?: string
          role?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "event_operators_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_operators_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "public_site_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_operators_model_id_fkey"
            columns: ["model_id"]
            isOneToOne: false
            referencedRelation: "compensation_models"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_operators_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "operators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_operators_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "public_site_operators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_operators_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["operator_id"]
          },
        ]
      }
      events: {
        Row: {
          capacity: number | null
          created_at: string
          currency: string | null
          deleted_at: string | null
          description: string | null
          ends_at: string | null
          event_type: Database["public"]["Enums"]["event_type"]
          id: string
          image_url: string | null
          is_active: boolean
          link: string | null
          location: string | null
          location_id: string | null
          name: string
          price_cents: number | null
          starts_at: string
          time_slots: Json | null
          updated_at: string
        }
        Insert: {
          capacity?: number | null
          created_at?: string
          currency?: string | null
          deleted_at?: string | null
          description?: string | null
          ends_at?: string | null
          event_type?: Database["public"]["Enums"]["event_type"]
          id?: string
          image_url?: string | null
          is_active?: boolean
          link?: string | null
          location?: string | null
          location_id?: string | null
          name: string
          price_cents?: number | null
          starts_at: string
          time_slots?: Json | null
          updated_at?: string
        }
        Update: {
          capacity?: number | null
          created_at?: string
          currency?: string | null
          deleted_at?: string | null
          description?: string | null
          ends_at?: string | null
          event_type?: Database["public"]["Enums"]["event_type"]
          id?: string
          image_url?: string | null
          is_active?: boolean
          link?: string | null
          location?: string | null
          location_id?: string | null
          name?: string
          price_cents?: number | null
          starts_at?: string
          time_slots?: Json | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "events_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "public_site_locations"
            referencedColumns: ["id"]
          },
        ]
      }
      expense_categories: {
        Row: {
          created_at: string
          description: string | null
          display_order: number
          id: string
          is_active: boolean
          legacy_category: string | null
          name: string
          rendiconto_bucket: string | null
          slug: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          legacy_category?: string | null
          name: string
          rendiconto_bucket?: string | null
          slug: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          legacy_category?: string | null
          name?: string
          rendiconto_bucket?: string | null
          slug?: string
          updated_at?: string
        }
        Relationships: []
      }
      expenses: {
        Row: {
          activity_id: string | null
          amount_cents: number
          attachment_path: string | null
          category: string
          category_id: string | null
          confirmed_at: string | null
          created_at: string
          created_by: string | null
          event_id: string | null
          expense_date: string
          id: string
          is_fixed: boolean
          lesson_id: string | null
          notes: string | null
          operator_id: string | null
          payout_id: string | null
          recurring_expense_id: string | null
          source: Database["public"]["Enums"]["expense_source"]
          updated_at: string
          vendor: string | null
          volunteer_reimbursement_id: string | null
        }
        Insert: {
          activity_id?: string | null
          amount_cents: number
          attachment_path?: string | null
          category: string
          category_id?: string | null
          confirmed_at?: string | null
          created_at?: string
          created_by?: string | null
          event_id?: string | null
          expense_date: string
          id?: string
          is_fixed?: boolean
          lesson_id?: string | null
          notes?: string | null
          operator_id?: string | null
          payout_id?: string | null
          recurring_expense_id?: string | null
          source?: Database["public"]["Enums"]["expense_source"]
          updated_at?: string
          vendor?: string | null
          volunteer_reimbursement_id?: string | null
        }
        Update: {
          activity_id?: string | null
          amount_cents?: number
          attachment_path?: string | null
          category?: string
          category_id?: string | null
          confirmed_at?: string | null
          created_at?: string
          created_by?: string | null
          event_id?: string | null
          expense_date?: string
          id?: string
          is_fixed?: boolean
          lesson_id?: string | null
          notes?: string | null
          operator_id?: string | null
          payout_id?: string | null
          recurring_expense_id?: string | null
          source?: Database["public"]["Enums"]["expense_source"]
          updated_at?: string
          vendor?: string | null
          volunteer_reimbursement_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "expenses_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "public_site_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["activity_id"]
          },
          {
            foreignKeyName: "expenses_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "expense_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "public_site_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lesson_occupancy"
            referencedColumns: ["lesson_id"]
          },
          {
            foreignKeyName: "expenses_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lessons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "operators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "public_site_operators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["operator_id"]
          },
          {
            foreignKeyName: "expenses_payout_id_fkey"
            columns: ["payout_id"]
            isOneToOne: false
            referencedRelation: "payouts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_recurring_expense_id_fkey"
            columns: ["recurring_expense_id"]
            isOneToOne: false
            referencedRelation: "recurring_expenses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_volunteer_reimbursement_id_fkey"
            columns: ["volunteer_reimbursement_id"]
            isOneToOne: false
            referencedRelation: "volunteer_reimbursements"
            referencedColumns: ["id"]
          },
        ]
      }
      feature_flags: {
        Row: {
          description: string | null
          enabled: boolean
          key: string
          payload: Json
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          description?: string | null
          enabled?: boolean
          key: string
          payload?: Json
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          description?: string | null
          enabled?: boolean
          key?: string
          payload?: Json
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      feedback: {
        Row: {
          client_id: string
          comment: string | null
          created_at: string
          event_id: string | null
          id: string
          kind: Database["public"]["Enums"]["feedback_kind"]
          lesson_id: string | null
          metadata: Json | null
          practice_id: string | null
          rating: number | null
          status: Database["public"]["Enums"]["feedback_status"]
          updated_at: string
        }
        Insert: {
          client_id: string
          comment?: string | null
          created_at?: string
          event_id?: string | null
          id?: string
          kind: Database["public"]["Enums"]["feedback_kind"]
          lesson_id?: string | null
          metadata?: Json | null
          practice_id?: string | null
          rating?: number | null
          status?: Database["public"]["Enums"]["feedback_status"]
          updated_at?: string
        }
        Update: {
          client_id?: string
          comment?: string | null
          created_at?: string
          event_id?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["feedback_kind"]
          lesson_id?: string | null
          metadata?: Json | null
          practice_id?: string | null
          rating?: number | null
          status?: Database["public"]["Enums"]["feedback_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "feedback_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feedback_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feedback_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "public_site_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feedback_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lesson_occupancy"
            referencedColumns: ["lesson_id"]
          },
          {
            foreignKeyName: "feedback_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lessons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feedback_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feedback_practice_id_fkey"
            columns: ["practice_id"]
            isOneToOne: false
            referencedRelation: "practices"
            referencedColumns: ["id"]
          },
        ]
      }
      journal_entries: {
        Row: {
          body: string
          client_id: string
          created_at: string
          id: string
          practice_id: string | null
          title: string | null
          updated_at: string
        }
        Insert: {
          body: string
          client_id: string
          created_at?: string
          id?: string
          practice_id?: string | null
          title?: string | null
          updated_at?: string
        }
        Update: {
          body?: string
          client_id?: string
          created_at?: string
          id?: string
          practice_id?: string | null
          title?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "journal_entries_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entries_practice_id_fkey"
            columns: ["practice_id"]
            isOneToOne: false
            referencedRelation: "practices"
            referencedColumns: ["id"]
          },
        ]
      }
      lessons: {
        Row: {
          activity_id: string
          assigned_client_id: string | null
          assigned_subscription_id: string | null
          booking_deadline_minutes: number | null
          cancel_deadline_minutes: number | null
          capacity: number
          deleted_at: string | null
          ends_at: string
          id: string
          is_individual: boolean
          location_id: string | null
          notes: string | null
          operator_id: string | null
          recurring_series_id: string | null
          starts_at: string
        }
        Insert: {
          activity_id: string
          assigned_client_id?: string | null
          assigned_subscription_id?: string | null
          booking_deadline_minutes?: number | null
          cancel_deadline_minutes?: number | null
          capacity: number
          deleted_at?: string | null
          ends_at: string
          id?: string
          is_individual?: boolean
          location_id?: string | null
          notes?: string | null
          operator_id?: string | null
          recurring_series_id?: string | null
          starts_at: string
        }
        Update: {
          activity_id?: string
          assigned_client_id?: string | null
          assigned_subscription_id?: string | null
          booking_deadline_minutes?: number | null
          cancel_deadline_minutes?: number | null
          capacity?: number
          deleted_at?: string | null
          ends_at?: string
          id?: string
          is_individual?: boolean
          location_id?: string | null
          notes?: string | null
          operator_id?: string | null
          recurring_series_id?: string | null
          starts_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "lessons_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lessons_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "public_site_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lessons_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["activity_id"]
          },
          {
            foreignKeyName: "lessons_assigned_client_id_fkey"
            columns: ["assigned_client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lessons_assigned_subscription_id_fkey"
            columns: ["assigned_subscription_id"]
            isOneToOne: false
            referencedRelation: "subscriptions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lessons_assigned_subscription_id_fkey"
            columns: ["assigned_subscription_id"]
            isOneToOne: false
            referencedRelation: "subscriptions_with_remaining"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lessons_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lessons_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "public_site_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lessons_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "operators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lessons_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "public_site_operators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lessons_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["operator_id"]
          },
        ]
      }
      locations: {
        Row: {
          access_notes: string | null
          address_street: string | null
          address_zip: string | null
          city: string
          created_at: string
          display_order: number
          id: string
          is_active: boolean
          latitude: number | null
          longitude: number | null
          map_url: string | null
          name: string
          notes: string | null
          province: string | null
          show_on_site: boolean
          slug: string
          updated_at: string
        }
        Insert: {
          access_notes?: string | null
          address_street?: string | null
          address_zip?: string | null
          city: string
          created_at?: string
          display_order?: number
          id?: string
          is_active?: boolean
          latitude?: number | null
          longitude?: number | null
          map_url?: string | null
          name: string
          notes?: string | null
          province?: string | null
          show_on_site?: boolean
          slug: string
          updated_at?: string
        }
        Update: {
          access_notes?: string | null
          address_street?: string | null
          address_zip?: string | null
          city?: string
          created_at?: string
          display_order?: number
          id?: string
          is_active?: boolean
          latitude?: number | null
          longitude?: number | null
          map_url?: string | null
          name?: string
          notes?: string | null
          province?: string | null
          show_on_site?: boolean
          slug?: string
          updated_at?: string
        }
        Relationships: []
      }
      member_applications: {
        Row: {
          accepted_privacy_at: string
          accepted_statute_at: string
          address_city: string | null
          address_province: string | null
          address_street: string | null
          address_zip: string | null
          birth_date: string
          birth_place: string | null
          birth_province: string | null
          channel: Database["public"]["Enums"]["member_application_channel"]
          client_id: string | null
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision_note: string | null
          email: string | null
          first_name: string
          fiscal_code: string | null
          guardian_consent_at: string | null
          guardian_email: string | null
          guardian_fiscal_code: string | null
          guardian_full_name: string | null
          guardian_phone: string | null
          guardian_relationship: string | null
          health_declaration: boolean | null
          id: string
          image_release: boolean | null
          last_name: string
          metadata: Json | null
          minor_at_submission: boolean
          pdf_path: string | null
          phone: string | null
          profile_id: string | null
          rejection_reason: string | null
          resolution_date: string | null
          status: Database["public"]["Enums"]["member_application_status"]
          submitted_at: string
          submitted_ip: unknown
          submitted_user_agent: string | null
          updated_at: string
          year: number
        }
        Insert: {
          accepted_privacy_at: string
          accepted_statute_at: string
          address_city?: string | null
          address_province?: string | null
          address_street?: string | null
          address_zip?: string | null
          birth_date: string
          birth_place?: string | null
          birth_province?: string | null
          channel: Database["public"]["Enums"]["member_application_channel"]
          client_id?: string | null
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          email?: string | null
          first_name: string
          fiscal_code?: string | null
          guardian_consent_at?: string | null
          guardian_email?: string | null
          guardian_fiscal_code?: string | null
          guardian_full_name?: string | null
          guardian_phone?: string | null
          guardian_relationship?: string | null
          health_declaration?: boolean | null
          id?: string
          image_release?: boolean | null
          last_name: string
          metadata?: Json | null
          minor_at_submission?: boolean
          pdf_path?: string | null
          phone?: string | null
          profile_id?: string | null
          rejection_reason?: string | null
          resolution_date?: string | null
          status?: Database["public"]["Enums"]["member_application_status"]
          submitted_at?: string
          submitted_ip?: unknown
          submitted_user_agent?: string | null
          updated_at?: string
          year: number
        }
        Update: {
          accepted_privacy_at?: string
          accepted_statute_at?: string
          address_city?: string | null
          address_province?: string | null
          address_street?: string | null
          address_zip?: string | null
          birth_date?: string
          birth_place?: string | null
          birth_province?: string | null
          channel?: Database["public"]["Enums"]["member_application_channel"]
          client_id?: string | null
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          email?: string | null
          first_name?: string
          fiscal_code?: string | null
          guardian_consent_at?: string | null
          guardian_email?: string | null
          guardian_fiscal_code?: string | null
          guardian_full_name?: string | null
          guardian_phone?: string | null
          guardian_relationship?: string | null
          health_declaration?: boolean | null
          id?: string
          image_release?: boolean | null
          last_name?: string
          metadata?: Json | null
          minor_at_submission?: boolean
          pdf_path?: string | null
          phone?: string | null
          profile_id?: string | null
          rejection_reason?: string | null
          resolution_date?: string | null
          status?: Database["public"]["Enums"]["member_application_status"]
          submitted_at?: string
          submitted_ip?: unknown
          submitted_user_agent?: string | null
          updated_at?: string
          year?: number
        }
        Relationships: [
          {
            foreignKeyName: "member_applications_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_applications_decided_by_fkey"
            columns: ["decided_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_applications_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_applications_year_fkey"
            columns: ["year"]
            isOneToOne: false
            referencedRelation: "association_years"
            referencedColumns: ["year"]
          },
        ]
      }
      member_fees: {
        Row: {
          amount_cents: number | null
          client_id: string
          created_at: string
          created_by: string | null
          id: string
          note: string | null
          paid_at: string | null
          refund_reason: string | null
          refunded_at: string | null
          status: Database["public"]["Enums"]["member_fee_status"]
          transaction_id: string | null
          updated_at: string
          waived_reason: string | null
          year: number
        }
        Insert: {
          amount_cents?: number | null
          client_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          note?: string | null
          paid_at?: string | null
          refund_reason?: string | null
          refunded_at?: string | null
          status?: Database["public"]["Enums"]["member_fee_status"]
          transaction_id?: string | null
          updated_at?: string
          waived_reason?: string | null
          year: number
        }
        Update: {
          amount_cents?: number | null
          client_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          note?: string | null
          paid_at?: string | null
          refund_reason?: string | null
          refunded_at?: string | null
          status?: Database["public"]["Enums"]["member_fee_status"]
          transaction_id?: string | null
          updated_at?: string
          waived_reason?: string | null
          year?: number
        }
        Relationships: [
          {
            foreignKeyName: "member_fees_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_fees_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_fees_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_fees_year_fkey"
            columns: ["year"]
            isOneToOne: false
            referencedRelation: "association_years"
            referencedColumns: ["year"]
          },
        ]
      }
      member_number_sequences: {
        Row: {
          last_number: number
          year: number
        }
        Insert: {
          last_number?: number
          year: number
        }
        Update: {
          last_number?: number
          year?: number
        }
        Relationships: []
      }
      members: {
        Row: {
          admitted_on: string
          application_id: string | null
          card_token: string
          cease_note: string | null
          cease_reason:
            | Database["public"]["Enums"]["member_cease_reason"]
            | null
          ceased_on: string | null
          client_id: string
          created_at: string
          id: string
          member_number: string
          resolution_date: string | null
          status: Database["public"]["Enums"]["member_status"]
          updated_at: string
        }
        Insert: {
          admitted_on: string
          application_id?: string | null
          card_token?: string
          cease_note?: string | null
          cease_reason?:
            | Database["public"]["Enums"]["member_cease_reason"]
            | null
          ceased_on?: string | null
          client_id: string
          created_at?: string
          id?: string
          member_number: string
          resolution_date?: string | null
          status?: Database["public"]["Enums"]["member_status"]
          updated_at?: string
        }
        Update: {
          admitted_on?: string
          application_id?: string | null
          card_token?: string
          cease_note?: string | null
          cease_reason?:
            | Database["public"]["Enums"]["member_cease_reason"]
            | null
          ceased_on?: string | null
          client_id?: string
          created_at?: string
          id?: string
          member_number?: string
          resolution_date?: string | null
          status?: Database["public"]["Enums"]["member_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "members_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "member_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "members_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: true
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      memberships: {
        Row: {
          client_id: string
          created_at: string
          created_by: string | null
          deleted_at: string | null
          expires_at: string
          id: string
          metadata: Json | null
          note: string | null
          price_cents_paid: number | null
          started_at: string
          status: Database["public"]["Enums"]["membership_status"]
          tier_id: string
          updated_at: string
        }
        Insert: {
          client_id: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          expires_at: string
          id?: string
          metadata?: Json | null
          note?: string | null
          price_cents_paid?: number | null
          started_at?: string
          status?: Database["public"]["Enums"]["membership_status"]
          tier_id: string
          updated_at?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          expires_at?: string
          id?: string
          metadata?: Json | null
          note?: string | null
          price_cents_paid?: number | null
          started_at?: string
          status?: Database["public"]["Enums"]["membership_status"]
          tier_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "memberships_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "memberships_tier_id_fkey"
            columns: ["tier_id"]
            isOneToOne: false
            referencedRelation: "pass_tiers"
            referencedColumns: ["id"]
          },
        ]
      }
      newsletter_campaigns: {
        Row: {
          archived: boolean
          bounced_count: number
          clicked_count: number
          content: string
          created_at: string
          created_by: string | null
          deleted_at: string | null
          delivered_count: number
          delivery_mode: string
          from_name_override: string | null
          id: string
          image_url: string | null
          marketing_campaign_id: string | null
          opened_count: number
          preview_text: string | null
          recipient_count: number
          recipients: Json | null
          scheduled_at: string | null
          sent_at: string | null
          status: Database["public"]["Enums"]["newsletter_campaign_status"]
          subject: string
          updated_at: string
        }
        Insert: {
          archived?: boolean
          bounced_count?: number
          clicked_count?: number
          content: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          delivered_count?: number
          delivery_mode?: string
          from_name_override?: string | null
          id?: string
          image_url?: string | null
          marketing_campaign_id?: string | null
          opened_count?: number
          preview_text?: string | null
          recipient_count?: number
          recipients?: Json | null
          scheduled_at?: string | null
          sent_at?: string | null
          status?: Database["public"]["Enums"]["newsletter_campaign_status"]
          subject: string
          updated_at?: string
        }
        Update: {
          archived?: boolean
          bounced_count?: number
          clicked_count?: number
          content?: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          delivered_count?: number
          delivery_mode?: string
          from_name_override?: string | null
          id?: string
          image_url?: string | null
          marketing_campaign_id?: string | null
          opened_count?: number
          preview_text?: string | null
          recipient_count?: number
          recipients?: Json | null
          scheduled_at?: string | null
          sent_at?: string | null
          status?: Database["public"]["Enums"]["newsletter_campaign_status"]
          subject?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "newsletter_campaigns_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "newsletter_campaigns_marketing_campaign_id_fkey"
            columns: ["marketing_campaign_id"]
            isOneToOne: false
            referencedRelation: "campaigns"
            referencedColumns: ["id"]
          },
        ]
      }
      newsletter_emails: {
        Row: {
          bounced_at: string | null
          campaign_id: string
          clicked_at: string | null
          client_id: string | null
          client_name: string
          created_at: string
          delivered_at: string | null
          email_address: string
          error_message: string | null
          id: string
          opened_at: string | null
          resend_id: string | null
          sent_at: string | null
          status: Database["public"]["Enums"]["newsletter_email_status"]
        }
        Insert: {
          bounced_at?: string | null
          campaign_id: string
          clicked_at?: string | null
          client_id?: string | null
          client_name: string
          created_at?: string
          delivered_at?: string | null
          email_address: string
          error_message?: string | null
          id?: string
          opened_at?: string | null
          resend_id?: string | null
          sent_at?: string | null
          status?: Database["public"]["Enums"]["newsletter_email_status"]
        }
        Update: {
          bounced_at?: string | null
          campaign_id?: string
          clicked_at?: string | null
          client_id?: string | null
          client_name?: string
          created_at?: string
          delivered_at?: string | null
          email_address?: string
          error_message?: string | null
          id?: string
          opened_at?: string | null
          resend_id?: string | null
          sent_at?: string | null
          status?: Database["public"]["Enums"]["newsletter_email_status"]
        }
        Relationships: [
          {
            foreignKeyName: "newsletter_emails_campaign_id_fkey"
            columns: ["campaign_id"]
            isOneToOne: false
            referencedRelation: "newsletter_campaigns"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "newsletter_emails_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      newsletter_extra_emails: {
        Row: {
          created_at: string
          deleted_at: string | null
          email: string
          id: string
          name: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          email: string
          id?: string
          name: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          email?: string
          id?: string
          name?: string
        }
        Relationships: []
      }
      newsletter_tracking_events: {
        Row: {
          created_at: string
          email_id: string
          event_data: Json | null
          event_type: Database["public"]["Enums"]["newsletter_event_type"]
          id: string
          occurred_at: string
        }
        Insert: {
          created_at?: string
          email_id: string
          event_data?: Json | null
          event_type: Database["public"]["Enums"]["newsletter_event_type"]
          id?: string
          occurred_at: string
        }
        Update: {
          created_at?: string
          email_id?: string
          event_data?: Json | null
          event_type?: Database["public"]["Enums"]["newsletter_event_type"]
          id?: string
          occurred_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "newsletter_tracking_events_email_id_fkey"
            columns: ["email_id"]
            isOneToOne: false
            referencedRelation: "newsletter_emails"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_logs: {
        Row: {
          body: string | null
          category: Database["public"]["Enums"]["notification_category"]
          channel: Database["public"]["Enums"]["notification_channel"]
          client_id: string
          data: Json | null
          delivered_at: string | null
          error_message: string | null
          expo_receipt_id: string | null
          id: string
          resend_id: string | null
          sent_at: string
          status: Database["public"]["Enums"]["notification_status"]
          title: string
        }
        Insert: {
          body?: string | null
          category: Database["public"]["Enums"]["notification_category"]
          channel: Database["public"]["Enums"]["notification_channel"]
          client_id: string
          data?: Json | null
          delivered_at?: string | null
          error_message?: string | null
          expo_receipt_id?: string | null
          id?: string
          resend_id?: string | null
          sent_at?: string
          status?: Database["public"]["Enums"]["notification_status"]
          title: string
        }
        Update: {
          body?: string | null
          category?: Database["public"]["Enums"]["notification_category"]
          channel?: Database["public"]["Enums"]["notification_channel"]
          client_id?: string
          data?: Json | null
          delivered_at?: string | null
          error_message?: string | null
          expo_receipt_id?: string | null
          id?: string
          resend_id?: string | null
          sent_at?: string
          status?: Database["public"]["Enums"]["notification_status"]
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_logs_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          category: Database["public"]["Enums"]["notification_category"]
          client_id: string
          created_at: string
          email_enabled: boolean
          id: string
          push_enabled: boolean
          updated_at: string
        }
        Insert: {
          category: Database["public"]["Enums"]["notification_category"]
          client_id: string
          created_at?: string
          email_enabled?: boolean
          id?: string
          push_enabled?: boolean
          updated_at?: string
        }
        Update: {
          category?: Database["public"]["Enums"]["notification_category"]
          client_id?: string
          created_at?: string
          email_enabled?: boolean
          id?: string
          push_enabled?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_preferences_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_queue: {
        Row: {
          attempts: number
          body: string
          category: Database["public"]["Enums"]["notification_category"]
          channel: Database["public"]["Enums"]["notification_channel"]
          client_id: string
          created_at: string
          data: Json | null
          error_message: string | null
          id: string
          last_attempt_at: string | null
          processed_at: string | null
          scheduled_for: string
          status: Database["public"]["Enums"]["notification_status"]
          title: string
        }
        Insert: {
          attempts?: number
          body: string
          category: Database["public"]["Enums"]["notification_category"]
          channel: Database["public"]["Enums"]["notification_channel"]
          client_id: string
          created_at?: string
          data?: Json | null
          error_message?: string | null
          id?: string
          last_attempt_at?: string | null
          processed_at?: string | null
          scheduled_for: string
          status?: Database["public"]["Enums"]["notification_status"]
          title: string
        }
        Update: {
          attempts?: number
          body?: string
          category?: Database["public"]["Enums"]["notification_category"]
          channel?: Database["public"]["Enums"]["notification_channel"]
          client_id?: string
          created_at?: string
          data?: Json | null
          error_message?: string | null
          id?: string
          last_attempt_at?: string | null
          processed_at?: string | null
          scheduled_for?: string
          status?: Database["public"]["Enums"]["notification_status"]
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_queue_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_reads: {
        Row: {
          announcement_id: string | null
          client_id: string
          id: string
          notification_log_id: string | null
          read_at: string
        }
        Insert: {
          announcement_id?: string | null
          client_id: string
          id?: string
          notification_log_id?: string | null
          read_at?: string
        }
        Update: {
          announcement_id?: string | null
          client_id?: string
          id?: string
          notification_log_id?: string | null
          read_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_reads_announcement_id_fkey"
            columns: ["announcement_id"]
            isOneToOne: false
            referencedRelation: "announcements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_reads_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_reads_notification_log_id_fkey"
            columns: ["notification_log_id"]
            isOneToOne: false
            referencedRelation: "notification_logs"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_settings: {
        Row: {
          client_id: string
          created_at: string
          quiet_hours_enabled: boolean
          quiet_hours_end: string | null
          quiet_hours_start: string | null
          updated_at: string
        }
        Insert: {
          client_id: string
          created_at?: string
          quiet_hours_enabled?: boolean
          quiet_hours_end?: string | null
          quiet_hours_start?: string | null
          updated_at?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          quiet_hours_enabled?: boolean
          quiet_hours_end?: string | null
          quiet_hours_start?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_settings_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: true
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      operators: {
        Row: {
          bio: string | null
          created_at: string | null
          deleted_at: string | null
          disciplines: string[] | null
          display_order: number | null
          engagement_type: Database["public"]["Enums"]["staff_engagement_type"]
          id: string
          image_url: string | null
          is_active: boolean
          is_admin: boolean | null
          is_visible_on_site: boolean
          name: string
          profile_id: string | null
          role: string
        }
        Insert: {
          bio?: string | null
          created_at?: string | null
          deleted_at?: string | null
          disciplines?: string[] | null
          display_order?: number | null
          engagement_type?: Database["public"]["Enums"]["staff_engagement_type"]
          id?: string
          image_url?: string | null
          is_active?: boolean
          is_admin?: boolean | null
          is_visible_on_site?: boolean
          name: string
          profile_id?: string | null
          role: string
        }
        Update: {
          bio?: string | null
          created_at?: string | null
          deleted_at?: string | null
          disciplines?: string[] | null
          display_order?: number | null
          engagement_type?: Database["public"]["Enums"]["staff_engagement_type"]
          id?: string
          image_url?: string | null
          is_active?: boolean
          is_admin?: boolean | null
          is_visible_on_site?: boolean
          name?: string
          profile_id?: string | null
          role?: string
        }
        Relationships: [
          {
            foreignKeyName: "operators_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      pass_tier_benefits: {
        Row: {
          benefit_type: Database["public"]["Enums"]["pass_benefit_type"]
          created_at: string
          description: string | null
          display_order: number
          id: string
          is_active: boolean
          label: string | null
          tier_id: string
          updated_at: string
          value_int: number | null
          value_percent: number | null
        }
        Insert: {
          benefit_type: Database["public"]["Enums"]["pass_benefit_type"]
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          label?: string | null
          tier_id: string
          updated_at?: string
          value_int?: number | null
          value_percent?: number | null
        }
        Update: {
          benefit_type?: Database["public"]["Enums"]["pass_benefit_type"]
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          label?: string | null
          tier_id?: string
          updated_at?: string
          value_int?: number | null
          value_percent?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "pass_tier_benefits_tier_id_fkey"
            columns: ["tier_id"]
            isOneToOne: false
            referencedRelation: "pass_tiers"
            referencedColumns: ["id"]
          },
        ]
      }
      pass_tiers: {
        Row: {
          created_at: string
          currency: string
          deleted_at: string | null
          description: string | null
          display_order: number
          id: string
          is_active: boolean
          name: string
          price_cents: number
          updated_at: string
          validity_days: number
        }
        Insert: {
          created_at?: string
          currency?: string
          deleted_at?: string | null
          description?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          name: string
          price_cents?: number
          updated_at?: string
          validity_days?: number
        }
        Update: {
          created_at?: string
          currency?: string
          deleted_at?: string | null
          description?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          name?: string
          price_cents?: number
          updated_at?: string
          validity_days?: number
        }
        Relationships: []
      }
      payout_rules: {
        Row: {
          cash_reserve_pct: number
          created_at: string
          created_by: string | null
          id: string
          marketing_pct: number
          month: string
          notes: string | null
          team_pct: number
          updated_at: string
        }
        Insert: {
          cash_reserve_pct?: number
          created_at?: string
          created_by?: string | null
          id?: string
          marketing_pct?: number
          month: string
          notes?: string | null
          team_pct?: number
          updated_at?: string
        }
        Update: {
          cash_reserve_pct?: number
          created_at?: string
          created_by?: string | null
          id?: string
          marketing_pct?: number
          month?: string
          notes?: string | null
          team_pct?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payout_rules_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      payouts: {
        Row: {
          amount_cents: number
          created_at: string
          created_by: string | null
          id: string
          month: string
          notes: string | null
          operator_id: string | null
          paid_at: string | null
          reason: string | null
          status: string
          updated_at: string
        }
        Insert: {
          amount_cents: number
          created_at?: string
          created_by?: string | null
          id?: string
          month: string
          notes?: string | null
          operator_id?: string | null
          paid_at?: string | null
          reason?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          amount_cents?: number
          created_at?: string
          created_by?: string | null
          id?: string
          month?: string
          notes?: string | null
          operator_id?: string | null
          paid_at?: string | null
          reason?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payouts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payouts_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "operators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payouts_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "public_site_operators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payouts_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["operator_id"]
          },
        ]
      }
      plan_activities: {
        Row: {
          activity_id: string
          created_at: string | null
          plan_id: string
        }
        Insert: {
          activity_id: string
          created_at?: string | null
          plan_id: string
        }
        Update: {
          activity_id?: string
          created_at?: string | null
          plan_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "plan_activities_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "plan_activities_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "public_site_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "plan_activities_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["activity_id"]
          },
          {
            foreignKeyName: "plan_activities_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "plan_activities_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "public_site_pricing"
            referencedColumns: ["id"]
          },
        ]
      }
      plans: {
        Row: {
          created_at: string | null
          currency: string | null
          deleted_at: string | null
          description: string | null
          discipline: string | null
          discount_percent: number | null
          entries: number | null
          id: string
          is_active: boolean | null
          name: string
          price_cents: number
          validity_days: number
        }
        Insert: {
          created_at?: string | null
          currency?: string | null
          deleted_at?: string | null
          description?: string | null
          discipline?: string | null
          discount_percent?: number | null
          entries?: number | null
          id?: string
          is_active?: boolean | null
          name: string
          price_cents: number
          validity_days: number
        }
        Update: {
          created_at?: string | null
          currency?: string | null
          deleted_at?: string | null
          description?: string | null
          discipline?: string | null
          discount_percent?: number | null
          entries?: number | null
          id?: string
          is_active?: boolean | null
          name?: string
          price_cents?: number
          validity_days?: number
        }
        Relationships: []
      }
      practice_activities: {
        Row: {
          activity_id: string
          created_at: string
          practice_id: string
        }
        Insert: {
          activity_id: string
          created_at?: string
          practice_id: string
        }
        Update: {
          activity_id?: string
          created_at?: string
          practice_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "practice_activities_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "practice_activities_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "public_site_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "practice_activities_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["activity_id"]
          },
          {
            foreignKeyName: "practice_activities_practice_id_fkey"
            columns: ["practice_id"]
            isOneToOne: false
            referencedRelation: "practices"
            referencedColumns: ["id"]
          },
        ]
      }
      practice_blocks: {
        Row: {
          block_type: Database["public"]["Enums"]["practice_block_type"]
          caption: string | null
          content: string
          created_at: string
          id: string
          sort_order: number
          step_id: string
        }
        Insert: {
          block_type: Database["public"]["Enums"]["practice_block_type"]
          caption?: string | null
          content: string
          created_at?: string
          id?: string
          sort_order: number
          step_id: string
        }
        Update: {
          block_type?: Database["public"]["Enums"]["practice_block_type"]
          caption?: string | null
          content?: string
          created_at?: string
          id?: string
          sort_order?: number
          step_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "practice_blocks_step_id_fkey"
            columns: ["step_id"]
            isOneToOne: false
            referencedRelation: "practice_steps"
            referencedColumns: ["id"]
          },
        ]
      }
      practice_steps: {
        Row: {
          created_at: string
          id: string
          practice_id: string
          sort_order: number
          title: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          practice_id: string
          sort_order: number
          title?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          practice_id?: string
          sort_order?: number
          title?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "practice_steps_practice_id_fkey"
            columns: ["practice_id"]
            isOneToOne: false
            referencedRelation: "practices"
            referencedColumns: ["id"]
          },
        ]
      }
      practice_user_state: {
        Row: {
          client_id: string
          completed_at: string | null
          current_step_index: number
          id: string
          is_favorite: boolean
          last_accessed_at: string
          practice_id: string
          started_at: string
          status: Database["public"]["Enums"]["practice_user_status"]
          time_spent_seconds: number
        }
        Insert: {
          client_id: string
          completed_at?: string | null
          current_step_index?: number
          id?: string
          is_favorite?: boolean
          last_accessed_at?: string
          practice_id: string
          started_at?: string
          status?: Database["public"]["Enums"]["practice_user_status"]
          time_spent_seconds?: number
        }
        Update: {
          client_id?: string
          completed_at?: string | null
          current_step_index?: number
          id?: string
          is_favorite?: boolean
          last_accessed_at?: string
          practice_id?: string
          started_at?: string
          status?: Database["public"]["Enums"]["practice_user_status"]
          time_spent_seconds?: number
        }
        Relationships: [
          {
            foreignKeyName: "practice_user_state_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "practice_user_state_practice_id_fkey"
            columns: ["practice_id"]
            isOneToOne: false
            referencedRelation: "practices"
            referencedColumns: ["id"]
          },
        ]
      }
      practices: {
        Row: {
          category: Database["public"]["Enums"]["practice_category"]
          cover_image_url: string | null
          created_at: string
          deleted_at: string | null
          description: string | null
          duration_minutes: number | null
          goals: Json | null
          id: string
          is_active: boolean
          is_featured: boolean
          level: Database["public"]["Enums"]["practice_level"]
          sort_order: number
          subtitle: string | null
          title: string
          updated_at: string
        }
        Insert: {
          category: Database["public"]["Enums"]["practice_category"]
          cover_image_url?: string | null
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          duration_minutes?: number | null
          goals?: Json | null
          id?: string
          is_active?: boolean
          is_featured?: boolean
          level?: Database["public"]["Enums"]["practice_level"]
          sort_order?: number
          subtitle?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          category?: Database["public"]["Enums"]["practice_category"]
          cover_image_url?: string | null
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          duration_minutes?: number | null
          goals?: Json | null
          id?: string
          is_active?: boolean
          is_featured?: boolean
          level?: Database["public"]["Enums"]["practice_level"]
          sort_order?: number
          subtitle?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          accepted_privacy_at: string | null
          accepted_terms_at: string | null
          avatar_url: string | null
          created_at: string | null
          deleted_at: string | null
          email: string | null
          full_name: string | null
          id: string
          notes: string | null
          phone: string | null
          role: Database["public"]["Enums"]["user_role"]
        }
        Insert: {
          accepted_privacy_at?: string | null
          accepted_terms_at?: string | null
          avatar_url?: string | null
          created_at?: string | null
          deleted_at?: string | null
          email?: string | null
          full_name?: string | null
          id: string
          notes?: string | null
          phone?: string | null
          role?: Database["public"]["Enums"]["user_role"]
        }
        Update: {
          accepted_privacy_at?: string | null
          accepted_terms_at?: string | null
          avatar_url?: string | null
          created_at?: string | null
          deleted_at?: string | null
          email?: string | null
          full_name?: string | null
          id?: string
          notes?: string | null
          phone?: string | null
          role?: Database["public"]["Enums"]["user_role"]
        }
        Relationships: []
      }
      promotions: {
        Row: {
          created_at: string
          deleted_at: string | null
          description: string | null
          discount_percent: number | null
          ends_at: string | null
          id: string
          image_url: string | null
          is_active: boolean
          link: string
          name: string
          plan_id: string | null
          starts_at: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          discount_percent?: number | null
          ends_at?: string | null
          id?: string
          image_url?: string | null
          is_active?: boolean
          link: string
          name: string
          plan_id?: string | null
          starts_at: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          discount_percent?: number | null
          ends_at?: string | null
          id?: string
          image_url?: string | null
          is_active?: boolean
          link?: string
          name?: string
          plan_id?: string | null
          starts_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "promotions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "promotions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "public_site_pricing"
            referencedColumns: ["id"]
          },
        ]
      }
      receipt_sequences: {
        Row: {
          last_number: number
          year: number
        }
        Insert: {
          last_number?: number
          year: number
        }
        Update: {
          last_number?: number
          year?: number
        }
        Relationships: []
      }
      receipts: {
        Row: {
          amount_cents: number
          causale: string
          created_at: string
          created_by: string | null
          full_number: string
          id: string
          issued_at: string
          issuer_snapshot: Json
          number: number
          pdf_path: string | null
          recipient_address: string | null
          recipient_fiscal_code: string | null
          recipient_name: string
          sent_at: string | null
          stamp_duty_cents: number
          transaction_id: string
          updated_at: string
          void_reason: string | null
          voided_at: string | null
          year: number
        }
        Insert: {
          amount_cents: number
          causale: string
          created_at?: string
          created_by?: string | null
          full_number: string
          id?: string
          issued_at?: string
          issuer_snapshot: Json
          number: number
          pdf_path?: string | null
          recipient_address?: string | null
          recipient_fiscal_code?: string | null
          recipient_name: string
          sent_at?: string | null
          stamp_duty_cents?: number
          transaction_id: string
          updated_at?: string
          void_reason?: string | null
          voided_at?: string | null
          year: number
        }
        Update: {
          amount_cents?: number
          causale?: string
          created_at?: string
          created_by?: string | null
          full_number?: string
          id?: string
          issued_at?: string
          issuer_snapshot?: Json
          number?: number
          pdf_path?: string | null
          recipient_address?: string | null
          recipient_fiscal_code?: string | null
          recipient_name?: string
          sent_at?: string | null
          stamp_duty_cents?: number
          transaction_id?: string
          updated_at?: string
          void_reason?: string | null
          voided_at?: string | null
          year?: number
        }
        Relationships: [
          {
            foreignKeyName: "receipts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "receipts_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: true
            referencedRelation: "transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      recurring_expenses: {
        Row: {
          amount_cents: number
          category_id: string
          created_at: string
          created_by: string | null
          day_of_month: number
          ends_on: string | null
          id: string
          is_active: boolean
          label: string
          last_generated_month: string | null
          notes: string | null
          starts_on: string
          updated_at: string
          vendor: string | null
        }
        Insert: {
          amount_cents: number
          category_id: string
          created_at?: string
          created_by?: string | null
          day_of_month?: number
          ends_on?: string | null
          id?: string
          is_active?: boolean
          label: string
          last_generated_month?: string | null
          notes?: string | null
          starts_on?: string
          updated_at?: string
          vendor?: string | null
        }
        Update: {
          amount_cents?: number
          category_id?: string
          created_at?: string
          created_by?: string | null
          day_of_month?: number
          ends_on?: string | null
          id?: string
          is_active?: boolean
          label?: string
          last_generated_month?: string | null
          notes?: string | null
          starts_on?: string
          updated_at?: string
          vendor?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "recurring_expenses_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "expense_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recurring_expenses_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      social_connections: {
        Row: {
          access_token: string
          account_id: string
          account_name: string | null
          created_at: string
          id: string
          instagram_business_id: string | null
          instagram_username: string | null
          is_active: boolean
          is_test: boolean
          last_error: string | null
          last_used_at: string | null
          operator_id: string
          page_id: string | null
          page_name: string | null
          permissions: string[] | null
          platform: Database["public"]["Enums"]["social_platform"]
          token_expires_at: string | null
          updated_at: string
        }
        Insert: {
          access_token: string
          account_id: string
          account_name?: string | null
          created_at?: string
          id?: string
          instagram_business_id?: string | null
          instagram_username?: string | null
          is_active?: boolean
          is_test?: boolean
          last_error?: string | null
          last_used_at?: string | null
          operator_id: string
          page_id?: string | null
          page_name?: string | null
          permissions?: string[] | null
          platform: Database["public"]["Enums"]["social_platform"]
          token_expires_at?: string | null
          updated_at?: string
        }
        Update: {
          access_token?: string
          account_id?: string
          account_name?: string | null
          created_at?: string
          id?: string
          instagram_business_id?: string | null
          instagram_username?: string | null
          is_active?: boolean
          is_test?: boolean
          last_error?: string | null
          last_used_at?: string | null
          operator_id?: string
          page_id?: string | null
          page_name?: string | null
          permissions?: string[] | null
          platform?: Database["public"]["Enums"]["social_platform"]
          token_expires_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "social_connections_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      stripe_events: {
        Row: {
          attempts: number
          error_message: string | null
          id: string
          livemode: boolean
          payload: Json
          processed_at: string | null
          received_at: string
          type: string
        }
        Insert: {
          attempts?: number
          error_message?: string | null
          id: string
          livemode?: boolean
          payload: Json
          processed_at?: string | null
          received_at?: string
          type: string
        }
        Update: {
          attempts?: number
          error_message?: string | null
          id?: string
          livemode?: boolean
          payload?: Json
          processed_at?: string | null
          received_at?: string
          type?: string
        }
        Relationships: []
      }
      stripe_payments: {
        Row: {
          amount_cents: number
          checkout_session_id: string | null
          client_id: string | null
          created_at: string
          currency: string
          failure_message: string | null
          fee_cents: number | null
          fee_expense_id: string | null
          id: string
          livemode: boolean
          net_cents: number | null
          payment_intent_id: string
          payment_method_type: string | null
          purpose: Database["public"]["Enums"]["stripe_purpose"]
          receipt_email: string | null
          status: Database["public"]["Enums"]["stripe_payment_status"]
          succeeded_at: string | null
          target_id: string | null
          transaction_id: string | null
          updated_at: string
        }
        Insert: {
          amount_cents: number
          checkout_session_id?: string | null
          client_id?: string | null
          created_at?: string
          currency?: string
          failure_message?: string | null
          fee_cents?: number | null
          fee_expense_id?: string | null
          id?: string
          livemode?: boolean
          net_cents?: number | null
          payment_intent_id: string
          payment_method_type?: string | null
          purpose: Database["public"]["Enums"]["stripe_purpose"]
          receipt_email?: string | null
          status?: Database["public"]["Enums"]["stripe_payment_status"]
          succeeded_at?: string | null
          target_id?: string | null
          transaction_id?: string | null
          updated_at?: string
        }
        Update: {
          amount_cents?: number
          checkout_session_id?: string | null
          client_id?: string | null
          created_at?: string
          currency?: string
          failure_message?: string | null
          fee_cents?: number | null
          fee_expense_id?: string | null
          id?: string
          livemode?: boolean
          net_cents?: number | null
          payment_intent_id?: string
          payment_method_type?: string | null
          purpose?: Database["public"]["Enums"]["stripe_purpose"]
          receipt_email?: string | null
          status?: Database["public"]["Enums"]["stripe_payment_status"]
          succeeded_at?: string | null
          target_id?: string | null
          transaction_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "stripe_payments_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stripe_payments_fee_expense_id_fkey"
            columns: ["fee_expense_id"]
            isOneToOne: false
            referencedRelation: "expenses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stripe_payments_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      stripe_refunds: {
        Row: {
          amount_cents: number
          created_at: string
          created_by: string | null
          id: string
          reason: string | null
          refund_id: string
          status: string | null
          stripe_payment_id: string
          transaction_id: string | null
        }
        Insert: {
          amount_cents: number
          created_at?: string
          created_by?: string | null
          id?: string
          reason?: string | null
          refund_id: string
          status?: string | null
          stripe_payment_id: string
          transaction_id?: string | null
        }
        Update: {
          amount_cents?: number
          created_at?: string
          created_by?: string | null
          id?: string
          reason?: string | null
          refund_id?: string
          status?: string | null
          stripe_payment_id?: string
          transaction_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "stripe_refunds_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stripe_refunds_stripe_payment_id_fkey"
            columns: ["stripe_payment_id"]
            isOneToOne: false
            referencedRelation: "stripe_payments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stripe_refunds_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      subscription_usages: {
        Row: {
          booking_id: string | null
          created_at: string | null
          delta: number
          id: string
          reason: string | null
          subscription_id: string
        }
        Insert: {
          booking_id?: string | null
          created_at?: string | null
          delta: number
          id?: string
          reason?: string | null
          subscription_id: string
        }
        Update: {
          booking_id?: string | null
          created_at?: string | null
          delta?: number
          id?: string
          reason?: string | null
          subscription_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "subscription_usages_subscription_id_fkey"
            columns: ["subscription_id"]
            isOneToOne: false
            referencedRelation: "subscriptions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscription_usages_subscription_id_fkey"
            columns: ["subscription_id"]
            isOneToOne: false
            referencedRelation: "subscriptions_with_remaining"
            referencedColumns: ["id"]
          },
        ]
      }
      subscriptions: {
        Row: {
          client_id: string | null
          created_at: string | null
          custom_entries: number | null
          custom_name: string | null
          custom_price_cents: number | null
          custom_validity_days: number | null
          deleted_at: string | null
          discount_percent: number | null
          discount_reason: string | null
          expires_at: string
          id: string
          metadata: Json | null
          plan_id: string
          started_at: string
          status: Database["public"]["Enums"]["subscription_status"]
        }
        Insert: {
          client_id?: string | null
          created_at?: string | null
          custom_entries?: number | null
          custom_name?: string | null
          custom_price_cents?: number | null
          custom_validity_days?: number | null
          deleted_at?: string | null
          discount_percent?: number | null
          discount_reason?: string | null
          expires_at: string
          id?: string
          metadata?: Json | null
          plan_id: string
          started_at?: string
          status?: Database["public"]["Enums"]["subscription_status"]
        }
        Update: {
          client_id?: string | null
          created_at?: string | null
          custom_entries?: number | null
          custom_name?: string | null
          custom_price_cents?: number | null
          custom_validity_days?: number | null
          deleted_at?: string | null
          discount_percent?: number | null
          discount_reason?: string | null
          expires_at?: string
          id?: string
          metadata?: Json | null
          plan_id?: string
          started_at?: string
          status?: Database["public"]["Enums"]["subscription_status"]
        }
        Relationships: [
          {
            foreignKeyName: "subscriptions_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscriptions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscriptions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "public_site_pricing"
            referencedColumns: ["id"]
          },
        ]
      }
      transactions: {
        Row: {
          amount_cents: number
          booking_id: string | null
          client_id: string | null
          created_at: string
          created_by: string | null
          currency: string
          description: string | null
          event_booking_id: string | null
          id: string
          is_commercial: boolean
          kind: Database["public"]["Enums"]["transaction_kind"]
          member_fee_id: string | null
          metadata: Json | null
          method: Database["public"]["Enums"]["payment_method"]
          note: string | null
          occurred_on: string
          refund_of_id: string | null
          source: Database["public"]["Enums"]["transaction_source"]
          status: Database["public"]["Enums"]["transaction_status"]
          stripe_payment_id: string | null
          subscription_id: string | null
          updated_at: string
        }
        Insert: {
          amount_cents: number
          booking_id?: string | null
          client_id?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          description?: string | null
          event_booking_id?: string | null
          id?: string
          is_commercial?: boolean
          kind: Database["public"]["Enums"]["transaction_kind"]
          member_fee_id?: string | null
          metadata?: Json | null
          method: Database["public"]["Enums"]["payment_method"]
          note?: string | null
          occurred_on?: string
          refund_of_id?: string | null
          source: Database["public"]["Enums"]["transaction_source"]
          status?: Database["public"]["Enums"]["transaction_status"]
          stripe_payment_id?: string | null
          subscription_id?: string | null
          updated_at?: string
        }
        Update: {
          amount_cents?: number
          booking_id?: string | null
          client_id?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          description?: string | null
          event_booking_id?: string | null
          id?: string
          is_commercial?: boolean
          kind?: Database["public"]["Enums"]["transaction_kind"]
          member_fee_id?: string | null
          metadata?: Json | null
          method?: Database["public"]["Enums"]["payment_method"]
          note?: string | null
          occurred_on?: string
          refund_of_id?: string | null
          source?: Database["public"]["Enums"]["transaction_source"]
          status?: Database["public"]["Enums"]["transaction_status"]
          stripe_payment_id?: string | null
          subscription_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "transactions_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "bookings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_event_booking_id_fkey"
            columns: ["event_booking_id"]
            isOneToOne: false
            referencedRelation: "event_bookings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_member_fee_id_fkey"
            columns: ["member_fee_id"]
            isOneToOne: false
            referencedRelation: "member_fees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_refund_of_id_fkey"
            columns: ["refund_of_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_stripe_payment_id_fkey"
            columns: ["stripe_payment_id"]
            isOneToOne: false
            referencedRelation: "stripe_payments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_subscription_id_fkey"
            columns: ["subscription_id"]
            isOneToOne: false
            referencedRelation: "subscriptions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_subscription_id_fkey"
            columns: ["subscription_id"]
            isOneToOne: false
            referencedRelation: "subscriptions_with_remaining"
            referencedColumns: ["id"]
          },
        ]
      }
      trials: {
        Row: {
          activity_id: string
          booked_at: string
          booking_id: string | null
          client_id: string
          converted_at: string | null
          converted_by: string | null
          converted_subscription_id: string | null
          created_at: string
          created_by: string | null
          id: string
          lesson_id: string | null
          note: string | null
          status: Database["public"]["Enums"]["trial_status"]
          updated_at: string
          was_member_at_booking: boolean
        }
        Insert: {
          activity_id: string
          booked_at?: string
          booking_id?: string | null
          client_id: string
          converted_at?: string | null
          converted_by?: string | null
          converted_subscription_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          lesson_id?: string | null
          note?: string | null
          status?: Database["public"]["Enums"]["trial_status"]
          updated_at?: string
          was_member_at_booking?: boolean
        }
        Update: {
          activity_id?: string
          booked_at?: string
          booking_id?: string | null
          client_id?: string
          converted_at?: string | null
          converted_by?: string | null
          converted_subscription_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          lesson_id?: string | null
          note?: string | null
          status?: Database["public"]["Enums"]["trial_status"]
          updated_at?: string
          was_member_at_booking?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "trials_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trials_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "public_site_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trials_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["activity_id"]
          },
          {
            foreignKeyName: "trials_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "bookings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trials_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trials_converted_by_fkey"
            columns: ["converted_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trials_converted_subscription_id_fkey"
            columns: ["converted_subscription_id"]
            isOneToOne: false
            referencedRelation: "subscriptions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trials_converted_subscription_id_fkey"
            columns: ["converted_subscription_id"]
            isOneToOne: false
            referencedRelation: "subscriptions_with_remaining"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trials_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lesson_occupancy"
            referencedColumns: ["lesson_id"]
          },
          {
            foreignKeyName: "trials_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lessons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trials_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["id"]
          },
        ]
      }
      user_preferences: {
        Row: {
          created_at: string
          goals: Json
          interests: Json
          onboarding_completed_at: string | null
          profile_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          goals?: Json
          interests?: Json
          onboarding_completed_at?: string | null
          profile_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          goals?: Json
          interests?: Json
          onboarding_completed_at?: string | null
          profile_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_preferences_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      volunteer_reimbursements: {
        Row: {
          amount_cents: number
          approved_at: string | null
          approved_by: string | null
          attachment_path: string
          created_at: string
          created_by: string | null
          description: string
          expense_id: string | null
          id: string
          note: string | null
          paid_at: string | null
          rejection_reason: string | null
          spent_on: string
          status: Database["public"]["Enums"]["reimbursement_status"]
          updated_at: string
          volunteer_id: string
        }
        Insert: {
          amount_cents: number
          approved_at?: string | null
          approved_by?: string | null
          attachment_path: string
          created_at?: string
          created_by?: string | null
          description: string
          expense_id?: string | null
          id?: string
          note?: string | null
          paid_at?: string | null
          rejection_reason?: string | null
          spent_on: string
          status?: Database["public"]["Enums"]["reimbursement_status"]
          updated_at?: string
          volunteer_id: string
        }
        Update: {
          amount_cents?: number
          approved_at?: string | null
          approved_by?: string | null
          attachment_path?: string
          created_at?: string
          created_by?: string | null
          description?: string
          expense_id?: string | null
          id?: string
          note?: string | null
          paid_at?: string | null
          rejection_reason?: string | null
          spent_on?: string
          status?: Database["public"]["Enums"]["reimbursement_status"]
          updated_at?: string
          volunteer_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "volunteer_reimbursements_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "volunteer_reimbursements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "volunteer_reimbursements_volunteer_id_fkey"
            columns: ["volunteer_id"]
            isOneToOne: false
            referencedRelation: "volunteer_registry"
            referencedColumns: ["volunteer_id"]
          },
          {
            foreignKeyName: "volunteer_reimbursements_volunteer_id_fkey"
            columns: ["volunteer_id"]
            isOneToOne: false
            referencedRelation: "volunteers"
            referencedColumns: ["id"]
          },
        ]
      }
      volunteers: {
        Row: {
          activity_note: string | null
          client_id: string | null
          created_at: string
          created_by: string | null
          ended_on: string | null
          fiscal_code: string | null
          full_name: string
          id: string
          insurance_note: string | null
          is_occasional: boolean
          operator_id: string | null
          started_on: string
          updated_at: string
        }
        Insert: {
          activity_note?: string | null
          client_id?: string | null
          created_at?: string
          created_by?: string | null
          ended_on?: string | null
          fiscal_code?: string | null
          full_name: string
          id?: string
          insurance_note?: string | null
          is_occasional?: boolean
          operator_id?: string | null
          started_on: string
          updated_at?: string
        }
        Update: {
          activity_note?: string | null
          client_id?: string | null
          created_at?: string
          created_by?: string | null
          ended_on?: string | null
          fiscal_code?: string | null
          full_name?: string
          id?: string
          insurance_note?: string | null
          is_occasional?: boolean
          operator_id?: string | null
          started_on?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "volunteers_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "volunteers_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "volunteers_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "operators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "volunteers_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "public_site_operators"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "volunteers_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["operator_id"]
          },
        ]
      }
      waitlist: {
        Row: {
          client_id: string | null
          created_at: string | null
          expires_at: string | null
          id: string
          lesson_id: string
          notified_at: string | null
          offered_at: string | null
          position: number | null
          status: Database["public"]["Enums"]["waitlist_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          client_id?: string | null
          created_at?: string | null
          expires_at?: string | null
          id?: string
          lesson_id: string
          notified_at?: string | null
          offered_at?: string | null
          position?: number | null
          status?: Database["public"]["Enums"]["waitlist_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          client_id?: string | null
          created_at?: string | null
          expires_at?: string | null
          id?: string
          lesson_id?: string
          notified_at?: string | null
          offered_at?: string | null
          position?: number | null
          status?: Database["public"]["Enums"]["waitlist_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "waitlist_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "waitlist_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lesson_occupancy"
            referencedColumns: ["lesson_id"]
          },
          {
            foreignKeyName: "waitlist_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "lessons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "waitlist_lesson_id_fkey"
            columns: ["lesson_id"]
            isOneToOne: false
            referencedRelation: "public_site_schedule"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "waitlist_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      financial_monthly_summary: {
        Row: {
          completed_payments_count: number | null
          gross_revenue_cents: number | null
          month: string | null
          refunded_payments_count: number | null
          refunds_cents: number | null
          revenue_cents: number | null
        }
        Relationships: []
      }
      lesson_occupancy: {
        Row: {
          booked_count: number | null
          capacity: number | null
          free_spots: number | null
          lesson_id: string | null
        }
        Relationships: []
      }
      member_registry: {
        Row: {
          address_city: string | null
          address_province: string | null
          address_street: string | null
          address_zip: string | null
          admitted_on: string | null
          birth_date: string | null
          birth_place: string | null
          birth_province: string | null
          can_vote: boolean | null
          cease_reason:
            | Database["public"]["Enums"]["member_cease_reason"]
            | null
          ceased_on: string | null
          client_id: string | null
          email: string | null
          fiscal_code: string | null
          full_name: string | null
          member_id: string | null
          member_number: string | null
          phone: string | null
          resolution_date: string | null
          status: Database["public"]["Enums"]["member_status"] | null
        }
        Relationships: [
          {
            foreignKeyName: "members_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: true
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
        ]
      }
      public_site_activities: {
        Row: {
          active_months: Json | null
          color: string | null
          created_at: string | null
          default_location_city: string | null
          default_location_slug: string | null
          description: string | null
          discipline: string | null
          duration_minutes: number | null
          group_id: string | null
          group_name: string | null
          group_slug: string | null
          icon_name: string | null
          id: string | null
          image_url: string | null
          is_active: boolean | null
          journey_structure: Json | null
          landing_subtitle: string | null
          landing_title: string | null
          name: string | null
          program_objectives: Json | null
          slug: string | null
          target_audience: Json | null
          updated_at: string | null
          why_participate: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "activities_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "activity_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activities_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "public_site_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      public_site_events: {
        Row: {
          created_at: string | null
          description: string | null
          end_date: string | null
          event_type: Database["public"]["Enums"]["event_type"] | null
          id: string | null
          image_url: string | null
          link_url: string | null
          location_city: string | null
          location_id: string | null
          location_map_url: string | null
          location_name: string | null
          location_slug: string | null
          registration_url: string | null
          start_date: string | null
          title: string | null
          updated_at: string | null
        }
        Relationships: [
          {
            foreignKeyName: "events_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "public_site_locations"
            referencedColumns: ["id"]
          },
        ]
      }
      public_site_groups: {
        Row: {
          activity_count: number | null
          color: string | null
          description: string | null
          display_order: number | null
          id: string | null
          image_url: string | null
          name: string | null
          seo_description: string | null
          seo_title: string | null
          slug: string | null
        }
        Relationships: []
      }
      public_site_locations: {
        Row: {
          access_notes: string | null
          address_street: string | null
          address_zip: string | null
          city: string | null
          display_order: number | null
          id: string | null
          latitude: number | null
          longitude: number | null
          map_url: string | null
          name: string | null
          province: string | null
          slug: string | null
        }
        Insert: {
          access_notes?: string | null
          address_street?: string | null
          address_zip?: string | null
          city?: string | null
          display_order?: number | null
          id?: string | null
          latitude?: number | null
          longitude?: number | null
          map_url?: string | null
          name?: string | null
          province?: string | null
          slug?: string | null
        }
        Update: {
          access_notes?: string | null
          address_street?: string | null
          address_zip?: string | null
          city?: string | null
          display_order?: number | null
          id?: string | null
          latitude?: number | null
          longitude?: number | null
          map_url?: string | null
          name?: string | null
          province?: string | null
          slug?: string | null
        }
        Relationships: []
      }
      public_site_operators: {
        Row: {
          bio: string | null
          display_order: number | null
          id: string | null
          image_alt: string | null
          image_url: string | null
          is_active: boolean | null
          name: string | null
          role: string | null
        }
        Insert: {
          bio?: string | null
          display_order?: number | null
          id?: string | null
          image_alt?: never
          image_url?: string | null
          is_active?: boolean | null
          name?: string | null
          role?: string | null
        }
        Update: {
          bio?: string | null
          display_order?: number | null
          id?: string | null
          image_alt?: never
          image_url?: string | null
          is_active?: boolean | null
          name?: string | null
          role?: string | null
        }
        Relationships: []
      }
      public_site_pricing: {
        Row: {
          activities: Json | null
          currency: string | null
          description: string | null
          discipline: string | null
          discount_percent: number | null
          entries: number | null
          id: string | null
          name: string | null
          price_cents: number | null
          validity_days: number | null
        }
        Relationships: []
      }
      public_site_schedule: {
        Row: {
          activity_color: string | null
          activity_id: string | null
          activity_name: string | null
          booked_count: number | null
          booking_deadline_minutes: number | null
          cancel_deadline_minutes: number | null
          capacity: number | null
          discipline: string | null
          ends_at: string | null
          free_spots: number | null
          id: string | null
          operator_id: string | null
          operator_name: string | null
          starts_at: string | null
        }
        Relationships: []
      }
      subscriptions_with_remaining: {
        Row: {
          client_id: string | null
          created_at: string | null
          custom_entries: number | null
          custom_name: string | null
          custom_price_cents: number | null
          custom_validity_days: number | null
          effective_entries: number | null
          expires_at: string | null
          id: string | null
          metadata: Json | null
          plan_id: string | null
          remaining_entries: number | null
          started_at: string | null
          status: Database["public"]["Enums"]["subscription_status"] | null
        }
        Relationships: [
          {
            foreignKeyName: "subscriptions_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscriptions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscriptions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "public_site_pricing"
            referencedColumns: ["id"]
          },
        ]
      }
      volunteer_registry: {
        Row: {
          activity_note: string | null
          ended_on: string | null
          fiscal_code: string | null
          full_name: string | null
          insurance_note: string | null
          is_active: boolean | null
          is_occasional: boolean | null
          started_on: string | null
          volunteer_id: string | null
        }
        Insert: {
          activity_note?: string | null
          ended_on?: string | null
          fiscal_code?: string | null
          full_name?: string | null
          insurance_note?: string | null
          is_active?: never
          is_occasional?: boolean | null
          started_on?: string | null
          volunteer_id?: string | null
        }
        Update: {
          activity_note?: string | null
          ended_on?: string | null
          fiscal_code?: string | null
          full_name?: string | null
          insurance_note?: string | null
          is_active?: never
          is_occasional?: boolean | null
          started_on?: string | null
          volunteer_id?: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      assign_membership: {
        Args: {
          p_client_id: string
          p_note?: string
          p_price_cents?: number
          p_started_at?: string
          p_tier_id: string
        }
        Returns: Json
      }
      book_event: { Args: { p_event_id: string }; Returns: Json }
      book_lesson: {
        Args: { p_lesson_id: string; p_subscription_id?: string }
        Returns: Json
      }
      book_trial_lesson: { Args: { p_lesson_id: string }; Returns: Json }
      calculate_compensation_v2: {
        Args: {
          p_month_end: string
          p_month_start: string
          p_operator_id?: string
        }
        Returns: {
          amount_cents: number
          breakdown: Json
          duration_minutes: number
          event_id: string
          lesson_id: string
          model_id: string
          model_name: string
          occurred_at: string
          operator_id: string
          operator_name: string
          participants: number
          revenue_cents: number
          title: string
        }[]
      }
      calculate_next_announcement_occurrence: {
        Args: {
          p_day_of_month: number
          p_day_of_week: number
          p_frequency: Database["public"]["Enums"]["announcement_recurrence_frequency"]
          p_from_date?: string
          p_time: string
        }
        Returns: string
      }
      calculate_operator_compensation: {
        Args: {
          p_month_end: string
          p_month_start: string
          p_operator_id?: string
        }
        Returns: {
          activity_name: string
          alice_share_cents: number
          generated_revenue_cents: number
          lesson_date: string
          lesson_duration_minutes: number
          lesson_id: string
          operator_id: string
          operator_name: string
          operator_payout_cents: number
          revenue_per_hour_cents: number
          room_rental_cents: number
          studio_margin_cents: number
        }[]
      }
      can_access_finance: { Args: never; Returns: boolean }
      cancel_booking: { Args: { p_booking_id: string }; Returns: Json }
      cancel_bussola_request: { Args: { p_request_id: string }; Returns: Json }
      cancel_event_booking: { Args: { p_booking_id: string }; Returns: Json }
      cancel_membership: { Args: { p_membership_id: string }; Returns: Json }
      confirm_expense: {
        Args: { p_amount_cents?: number; p_expense_id: string }
        Returns: Json
      }
      deactivate_device_token: { Args: { p_token: string }; Returns: Json }
      delete_campaign: { Args: { campaign_id: string }; Returns: undefined }
      generate_recurring_expenses: { Args: { p_month?: string }; Returns: Json }
      generate_slug_from_discipline: {
        Args: { discipline_text: string }
        Returns: string
      }
      get_activity_booking_counts: {
        Args: never
        Returns: {
          activity_id: string
          booking_count: number
        }[]
      }
      get_auth_email_stats: {
        Args: { p_user_id: string }
        Returns: {
          bounced_count: number
          failed_count: number
          last_sent_at: string
          last_status: string
          total_sent: number
        }[]
      }
      get_event_booking_count: { Args: { p_event_id: string }; Returns: number }
      get_events_booking_counts: {
        Args: { p_event_ids: string[] }
        Returns: {
          booked_count: number
          event_id: string
        }[]
      }
      get_financial_kpis: {
        Args: { p_month_end?: string; p_month_start?: string }
        Returns: Json
      }
      get_journey_summary: { Args: never; Returns: Json }
      get_journey_timeline: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: Json
      }
      get_monthly_revenue_by_client: {
        Args: { p_month_end: string; p_month_start: string }
        Returns: {
          client_email: string
          client_id: string
          client_name: string
          subscription_count: number
          total_revenue_cents: number
        }[]
      }
      get_monthly_revenue_by_plan: {
        Args: { p_month_end: string; p_month_start: string }
        Returns: {
          plan_id: string
          plan_name: string
          subscription_count: number
          total_revenue_cents: number
        }[]
      }
      get_my_client_id: { Args: never; Returns: string }
      get_my_member_card: { Args: never; Returns: Json }
      get_my_membership: { Args: never; Returns: Json }
      get_my_membership_status: { Args: never; Returns: Json }
      get_my_notification_settings: { Args: never; Returns: Json }
      get_my_notifications: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: Json
      }
      get_practice_metrics: { Args: never; Returns: Json }
      get_revenue_breakdown: {
        Args: { p_month_end?: string; p_month_start?: string }
        Returns: Json
      }
      get_unread_notifications_count: { Args: never; Returns: number }
      is_admin: { Args: never; Returns: boolean }
      is_finance: { Args: never; Returns: boolean }
      is_staff: { Args: never; Returns: boolean }
      issue_receipt: {
        Args: { p_causale?: string; p_transaction_id: string }
        Returns: Json
      }
      join_waitlist: { Args: { p_lesson_id: string }; Returns: Json }
      leave_waitlist: { Args: { p_lesson_id: string }; Returns: Json }
      mark_all_notifications_read: { Args: never; Returns: number }
      mark_notification_read: {
        Args: { p_announcement_id?: string; p_notification_log_id?: string }
        Returns: boolean
      }
      process_recurring_announcements: { Args: never; Returns: undefined }
      promote_profile_to_operator: {
        Args: { p_profile_id: string }
        Returns: Json
      }
      queue_birthday: { Args: never; Returns: Json }
      queue_entries_low: { Args: never; Returns: Json }
      queue_feedback_request: {
        Args: {
          p_client_id: string
          p_kind: Database["public"]["Enums"]["feedback_kind"]
          p_scheduled_for?: string
          p_target_id?: string
        }
        Returns: Json
      }
      queue_lesson_reminders: { Args: never; Returns: Json }
      queue_new_event:
        | {
            Args: {
              p_event_date: string
              p_event_id: string
              p_event_name: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_event_date: string
              p_event_id: string
              p_event_name: string
              p_send_email?: boolean
              p_send_push?: boolean
            }
            Returns: Json
          }
      queue_re_engagement: { Args: never; Returns: Json }
      queue_subscription_expiry: { Args: never; Returns: Json }
      register_device_token: {
        Args: {
          p_app_version?: string
          p_device_id?: string
          p_platform?: string
          p_token: string
        }
        Returns: Json
      }
      request_bussola: {
        Args: { p_note?: string; p_preferred_at?: string }
        Returns: Json
      }
      set_notification_quiet_hours: {
        Args: { p_enabled: boolean; p_end?: string; p_start?: string }
        Returns: Json
      }
      staff_book_event: {
        Args: { p_client_id: string; p_event_id: string }
        Returns: Json
      }
      staff_book_lesson: {
        Args: {
          p_client_id: string
          p_lesson_id: string
          p_subscription_id?: string
        }
        Returns: Json
      }
      staff_book_trial: {
        Args: { p_client_id: string; p_lesson_id: string }
        Returns: Json
      }
      staff_cancel_booking: { Args: { p_booking_id: string }; Returns: Json }
      staff_cancel_event_booking: {
        Args: { p_booking_id: string }
        Returns: Json
      }
      staff_create_client_and_book_trial: {
        Args: {
          p_email: string
          p_first_name: string
          p_last_name: string
          p_lesson_id: string
          p_phone: string
        }
        Returns: Json
      }
      staff_create_member_application: {
        Args: { p_client_id: string; p_payload: Json }
        Returns: Json
      }
      staff_decide_member_applications: {
        Args: {
          p_application_ids: string[]
          p_approve: boolean
          p_note?: string
          p_rejection_reason?: string
          p_resolution_date?: string
        }
        Returns: Json
      }
      staff_freeze_compensation: {
        Args: {
          p_month_end: string
          p_month_start: string
          p_operator_id?: string
        }
        Returns: Json
      }
      staff_get_member_statuses: {
        Args: { p_client_ids: string[] }
        Returns: Json
      }
      staff_get_user_email_status: {
        Args: { p_user_id: string }
        Returns: Json
      }
      staff_mark_compensation_paid: {
        Args: { p_entry_ids: string[] }
        Returns: Json
      }
      staff_pay_member_fee: {
        Args: {
          p_amount_cents?: number
          p_client_id: string
          p_issue_receipt?: boolean
          p_method?: Database["public"]["Enums"]["payment_method"]
          p_note?: string
          p_occurred_on?: string
          p_year: number
        }
        Returns: Json
      }
      staff_pay_volunteer_reimbursement: {
        Args: { p_reimbursement_id: string }
        Returns: Json
      }
      staff_refund_transaction: {
        Args: {
          p_amount_cents: number
          p_reason: string
          p_transaction_id: string
        }
        Returns: Json
      }
      staff_register_payment: { Args: { p_payload: Json }; Returns: Json }
      staff_set_member_fee: {
        Args: {
          p_amount_cents?: number
          p_client_id: string
          p_note?: string
          p_status: Database["public"]["Enums"]["member_fee_status"]
          p_year: number
        }
        Returns: Json
      }
      staff_settle_transaction: {
        Args: {
          p_causale?: string
          p_issue_receipt?: boolean
          p_method?: Database["public"]["Enums"]["payment_method"]
          p_occurred_on?: string
          p_transaction_id: string
        }
        Returns: Json
      }
      staff_unconvert_trial: {
        Args: { p_reason: string; p_trial_id: string }
        Returns: Json
      }
      staff_update_booking_status: {
        Args: {
          p_booking_id: string
          p_status: Database["public"]["Enums"]["booking_status"]
        }
        Returns: Json
      }
      submit_feedback: {
        Args: {
          p_comment?: string
          p_kind: Database["public"]["Enums"]["feedback_kind"]
          p_rating?: number
          p_target_id?: string
        }
        Returns: Json
      }
      submit_member_application: { Args: { p_payload: Json }; Returns: Json }
      void_receipt: {
        Args: { p_reason: string; p_receipt_id: string }
        Returns: Json
      }
    }
    Enums: {
      activity_category: "comunita" | "partners" | "core" | "esperienze"
      announcement_recurrence_frequency:
        | "daily"
        | "weekly"
        | "biweekly"
        | "monthly"
      booking_status: "booked" | "canceled" | "attended" | "no_show"
      bug_status: "open" | "in_progress" | "resolved" | "closed"
      bussola_request_status:
        | "pending"
        | "scheduled"
        | "completed"
        | "cancelled"
      campaign_content_type:
        | "brief"
        | "push_notification"
        | "newsletter"
        | "instagram_post"
        | "instagram_story"
        | "instagram_reel"
        | "instagram_carousel"
        | "facebook_post"
      campaign_tone:
        | "formale"
        | "amichevole"
        | "urgente"
        | "entusiasta"
        | "professionale"
        | "empatico"
        | "diretto"
        | "esclusivo"
      campaign_type: "promo" | "evento" | "annuncio" | "corso_nuovo"
      compensation_component_kind:
        | "fixed_per_lesson"
        | "fixed_per_hour"
        | "per_participant"
        | "percent_of_revenue"
        | "room_fee_percent"
      compensation_entry_status: "pending" | "approved" | "paid"
      content_status:
        | "pending"
        | "generated"
        | "edited"
        | "scheduled"
        | "sent"
        | "published"
        | "failed"
        | "skipped"
      event_type: "evento" | "laboratorio" | "incontro"
      expense_source:
        | "manual"
        | "recurring"
        | "payout"
        | "stripe_fee"
        | "volunteer"
      feedback_kind: "practice" | "lesson" | "onboarding" | "event"
      feedback_status: "new" | "reviewed" | "archived"
      marketing_campaign_status:
        | "draft"
        | "ai_generating"
        | "pending_review"
        | "scheduled"
        | "executing"
        | "completed"
        | "failed"
      member_application_channel: "app" | "site" | "paper"
      member_application_status:
        | "pending"
        | "approved"
        | "rejected"
        | "withdrawn"
      member_cease_reason:
        | "recesso"
        | "esclusione"
        | "decadenza"
        | "mancato_pagamento"
        | "decesso"
      member_fee_status: "due" | "paid" | "waived" | "refunded"
      member_status: "pending_admission" | "active" | "ceased"
      membership_status: "active" | "expired" | "cancelled"
      newsletter_campaign_status:
        | "draft"
        | "scheduled"
        | "sending"
        | "sent"
        | "failed"
      newsletter_email_status:
        | "pending"
        | "sent"
        | "delivered"
        | "opened"
        | "clicked"
        | "bounced"
        | "complained"
        | "failed"
      newsletter_event_type:
        | "delivered"
        | "opened"
        | "clicked"
        | "bounced"
        | "complained"
      notification_category:
        | "lesson_reminder"
        | "subscription_expiry"
        | "entries_low"
        | "re_engagement"
        | "first_lesson"
        | "milestone"
        | "birthday"
        | "new_event"
        | "announcement"
        | "practice_reminder"
        | "practice_resume"
        | "journal_reminder"
        | "feedback_request"
        | "waitlist_promotion"
        | "member_application_decided"
        | "membership_fee_due"
        | "trial_followup"
      notification_channel: "push" | "email"
      notification_status:
        | "pending"
        | "sent"
        | "delivered"
        | "failed"
        | "skipped"
      pass_benefit_type:
        | "subscription_discount"
        | "event_discount"
        | "bussola"
        | "community_access"
        | "priority_booking"
        | "other"
      payment_method: "cash" | "bank_transfer" | "stripe" | "other"
      practice_block_type: "text" | "image" | "audio" | "video"
      practice_category:
        | "meditazione"
        | "corpo"
        | "respiro"
        | "scrittura"
        | "rilassamento"
      practice_level: "principiante" | "intermedio" | "avanzato"
      practice_user_status: "started" | "completed"
      reimbursement_status: "pending" | "approved" | "paid" | "rejected"
      social_platform: "instagram" | "facebook"
      staff_engagement_type: "paid" | "volunteer"
      stripe_payment_status:
        | "created"
        | "processing"
        | "succeeded"
        | "failed"
        | "canceled"
        | "refunded"
        | "partially_refunded"
      stripe_purpose:
        | "membership_fee"
        | "subscription"
        | "event"
        | "donation"
        | "other"
      subscription_status: "active" | "completed" | "expired" | "canceled"
      transaction_kind:
        | "membership_fee"
        | "subscription"
        | "event"
        | "trial"
        | "donation"
        | "commercial"
        | "other"
      transaction_source: "studio" | "app" | "site"
      transaction_status:
        | "pending"
        | "paid"
        | "refunded"
        | "partially_refunded"
        | "void"
      trial_status: "booked" | "attended" | "no_show" | "canceled" | "converted"
      user_role: "user" | "operator" | "admin" | "finance"
      waitlist_status: "waiting" | "offered" | "booked" | "expired" | "left"
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
    Enums: {
      activity_category: ["comunita", "partners", "core", "esperienze"],
      announcement_recurrence_frequency: [
        "daily",
        "weekly",
        "biweekly",
        "monthly",
      ],
      booking_status: ["booked", "canceled", "attended", "no_show"],
      bug_status: ["open", "in_progress", "resolved", "closed"],
      bussola_request_status: [
        "pending",
        "scheduled",
        "completed",
        "cancelled",
      ],
      campaign_content_type: [
        "brief",
        "push_notification",
        "newsletter",
        "instagram_post",
        "instagram_story",
        "instagram_reel",
        "instagram_carousel",
        "facebook_post",
      ],
      campaign_tone: [
        "formale",
        "amichevole",
        "urgente",
        "entusiasta",
        "professionale",
        "empatico",
        "diretto",
        "esclusivo",
      ],
      campaign_type: ["promo", "evento", "annuncio", "corso_nuovo"],
      compensation_component_kind: [
        "fixed_per_lesson",
        "fixed_per_hour",
        "per_participant",
        "percent_of_revenue",
        "room_fee_percent",
      ],
      compensation_entry_status: ["pending", "approved", "paid"],
      content_status: [
        "pending",
        "generated",
        "edited",
        "scheduled",
        "sent",
        "published",
        "failed",
        "skipped",
      ],
      event_type: ["evento", "laboratorio", "incontro"],
      expense_source: [
        "manual",
        "recurring",
        "payout",
        "stripe_fee",
        "volunteer",
      ],
      feedback_kind: ["practice", "lesson", "onboarding", "event"],
      feedback_status: ["new", "reviewed", "archived"],
      marketing_campaign_status: [
        "draft",
        "ai_generating",
        "pending_review",
        "scheduled",
        "executing",
        "completed",
        "failed",
      ],
      member_application_channel: ["app", "site", "paper"],
      member_application_status: [
        "pending",
        "approved",
        "rejected",
        "withdrawn",
      ],
      member_cease_reason: [
        "recesso",
        "esclusione",
        "decadenza",
        "mancato_pagamento",
        "decesso",
      ],
      member_fee_status: ["due", "paid", "waived", "refunded"],
      member_status: ["pending_admission", "active", "ceased"],
      membership_status: ["active", "expired", "cancelled"],
      newsletter_campaign_status: [
        "draft",
        "scheduled",
        "sending",
        "sent",
        "failed",
      ],
      newsletter_email_status: [
        "pending",
        "sent",
        "delivered",
        "opened",
        "clicked",
        "bounced",
        "complained",
        "failed",
      ],
      newsletter_event_type: [
        "delivered",
        "opened",
        "clicked",
        "bounced",
        "complained",
      ],
      notification_category: [
        "lesson_reminder",
        "subscription_expiry",
        "entries_low",
        "re_engagement",
        "first_lesson",
        "milestone",
        "birthday",
        "new_event",
        "announcement",
        "practice_reminder",
        "practice_resume",
        "journal_reminder",
        "feedback_request",
        "waitlist_promotion",
        "member_application_decided",
        "membership_fee_due",
        "trial_followup",
      ],
      notification_channel: ["push", "email"],
      notification_status: [
        "pending",
        "sent",
        "delivered",
        "failed",
        "skipped",
      ],
      pass_benefit_type: [
        "subscription_discount",
        "event_discount",
        "bussola",
        "community_access",
        "priority_booking",
        "other",
      ],
      payment_method: ["cash", "bank_transfer", "stripe", "other"],
      practice_block_type: ["text", "image", "audio", "video"],
      practice_category: [
        "meditazione",
        "corpo",
        "respiro",
        "scrittura",
        "rilassamento",
      ],
      practice_level: ["principiante", "intermedio", "avanzato"],
      practice_user_status: ["started", "completed"],
      reimbursement_status: ["pending", "approved", "paid", "rejected"],
      social_platform: ["instagram", "facebook"],
      staff_engagement_type: ["paid", "volunteer"],
      stripe_payment_status: [
        "created",
        "processing",
        "succeeded",
        "failed",
        "canceled",
        "refunded",
        "partially_refunded",
      ],
      stripe_purpose: [
        "membership_fee",
        "subscription",
        "event",
        "donation",
        "other",
      ],
      subscription_status: ["active", "completed", "expired", "canceled"],
      transaction_kind: [
        "membership_fee",
        "subscription",
        "event",
        "trial",
        "donation",
        "commercial",
        "other",
      ],
      transaction_source: ["studio", "app", "site"],
      transaction_status: [
        "pending",
        "paid",
        "refunded",
        "partially_refunded",
        "void",
      ],
      trial_status: ["booked", "attended", "no_show", "canceled", "converted"],
      user_role: ["user", "operator", "admin", "finance"],
      waitlist_status: ["waiting", "offered", "booked", "expired", "left"],
    },
  },
} as const

