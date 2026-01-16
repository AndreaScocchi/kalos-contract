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
    PostgrestVersion: "13.0.5"
  }
  public: {
    Tables: {
      activities: {
        Row: {
          active_months: Json | null
          color: string | null
          created_at: string | null
          deleted_at: string | null
          description: string | null
          discipline: string
          duration_minutes: number | null
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
          updated_at: string | null
          why_participate: Json | null
        }
        Insert: {
          active_months?: Json | null
          color?: string | null
          created_at?: string | null
          deleted_at?: string | null
          description?: string | null
          discipline: string
          duration_minutes?: number | null
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
          updated_at?: string | null
          why_participate?: Json | null
        }
        Update: {
          active_months?: Json | null
          color?: string | null
          created_at?: string | null
          deleted_at?: string | null
          description?: string | null
          discipline?: string
          duration_minutes?: number | null
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
          updated_at?: string | null
          why_participate?: Json | null
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
          link_label: string | null
          link_url: string | null
          starts_at: string
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
          link_label?: string | null
          link_url?: string | null
          starts_at?: string
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
          link_label?: string | null
          link_url?: string | null
          starts_at?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      bookings: {
        Row: {
          client_id: string | null
          created_at: string | null
          id: string
          lesson_id: string
          status: Database["public"]["Enums"]["booking_status"]
          subscription_id: string | null
        }
        Insert: {
          client_id?: string | null
          created_at?: string | null
          id?: string
          lesson_id: string
          status?: Database["public"]["Enums"]["booking_status"]
          subscription_id?: string | null
        }
        Update: {
          client_id?: string | null
          created_at?: string | null
          id?: string
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
      events: {
        Row: {
          capacity: number | null
          created_at: string
          currency: string | null
          deleted_at: string | null
          description: string | null
          ends_at: string | null
          id: string
          image_url: string | null
          is_active: boolean
          link: string | null
          location: string | null
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
          id?: string
          image_url?: string | null
          is_active?: boolean
          link?: string | null
          location?: string | null
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
          id?: string
          image_url?: string | null
          is_active?: boolean
          link?: string | null
          location?: string | null
          name?: string
          price_cents?: number | null
          starts_at?: string
          time_slots?: Json | null
          updated_at?: string
        }
        Relationships: []
      }
      expenses: {
        Row: {
          activity_id: string | null
          amount_cents: number
          category: string
          created_at: string
          created_by: string | null
          event_id: string | null
          expense_date: string
          id: string
          is_fixed: boolean
          lesson_id: string | null
          notes: string | null
          operator_id: string | null
          updated_at: string
          vendor: string | null
        }
        Insert: {
          activity_id?: string | null
          amount_cents: number
          category: string
          created_at?: string
          created_by?: string | null
          event_id?: string | null
          expense_date: string
          id?: string
          is_fixed?: boolean
          lesson_id?: string | null
          notes?: string | null
          operator_id?: string | null
          updated_at?: string
          vendor?: string | null
        }
        Update: {
          activity_id?: string | null
          amount_cents?: number
          category?: string
          created_at?: string
          created_by?: string | null
          event_id?: string | null
          expense_date?: string
          id?: string
          is_fixed?: boolean
          lesson_id?: string | null
          notes?: string | null
          operator_id?: string | null
          updated_at?: string
          vendor?: string | null
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
          id: string
          image_url: string | null
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
          id?: string
          image_url?: string | null
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
          id?: string
          image_url?: string | null
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
      operators: {
        Row: {
          bio: string | null
          created_at: string | null
          deleted_at: string | null
          disciplines: string[] | null
          id: string
          is_active: boolean
          is_admin: boolean | null
          name: string
          profile_id: string | null
          role: string
        }
        Insert: {
          bio?: string | null
          created_at?: string | null
          deleted_at?: string | null
          disciplines?: string[] | null
          id?: string
          is_active?: boolean
          is_admin?: boolean | null
          name: string
          profile_id?: string | null
          role: string
        }
        Update: {
          bio?: string | null
          created_at?: string | null
          deleted_at?: string | null
          disciplines?: string[] | null
          id?: string
          is_active?: boolean
          is_admin?: boolean | null
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
      waitlist: {
        Row: {
          created_at: string | null
          id: string
          lesson_id: string
          user_id: string
        }
        Insert: {
          created_at?: string | null
          id?: string
          lesson_id: string
          user_id: string
        }
        Update: {
          created_at?: string | null
          id?: string
          lesson_id?: string
          user_id?: string
        }
        Relationships: [
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
      public_site_activities: {
        Row: {
          active_months: Json | null
          color: string | null
          created_at: string | null
          description: string | null
          discipline: string | null
          duration_minutes: number | null
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
        Insert: {
          active_months?: Json | null
          color?: string | null
          created_at?: string | null
          description?: string | null
          discipline?: string | null
          duration_minutes?: number | null
          icon_name?: string | null
          id?: string | null
          image_url?: string | null
          is_active?: boolean | null
          journey_structure?: Json | null
          landing_subtitle?: string | null
          landing_title?: string | null
          name?: string | null
          program_objectives?: Json | null
          slug?: string | null
          target_audience?: Json | null
          updated_at?: string | null
          why_participate?: Json | null
        }
        Update: {
          active_months?: Json | null
          color?: string | null
          created_at?: string | null
          description?: string | null
          discipline?: string | null
          duration_minutes?: number | null
          icon_name?: string | null
          id?: string | null
          image_url?: string | null
          is_active?: boolean | null
          journey_structure?: Json | null
          landing_subtitle?: string | null
          landing_title?: string | null
          name?: string | null
          program_objectives?: Json | null
          slug?: string | null
          target_audience?: Json | null
          updated_at?: string | null
          why_participate?: Json | null
        }
        Relationships: []
      }
      public_site_events: {
        Row: {
          created_at: string | null
          description: string | null
          end_date: string | null
          id: string | null
          image_url: string | null
          link_url: string | null
          registration_url: string | null
          start_date: string | null
          title: string | null
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          description?: string | null
          end_date?: string | null
          id?: string | null
          image_url?: string | null
          link_url?: string | null
          registration_url?: string | null
          start_date?: string | null
          title?: string | null
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          description?: string | null
          end_date?: string | null
          id?: string | null
          image_url?: string | null
          link_url?: string | null
          registration_url?: string | null
          start_date?: string | null
          title?: string | null
          updated_at?: string | null
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
          display_order?: never
          id?: string | null
          image_alt?: never
          image_url?: never
          is_active?: boolean | null
          name?: string | null
          role?: string | null
        }
        Update: {
          bio?: string | null
          display_order?: never
          id?: string | null
          image_alt?: never
          image_url?: never
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
    }
    Functions: {
      book_event: { Args: { p_event_id: string }; Returns: Json }
      book_lesson: {
        Args: { p_lesson_id: string; p_subscription_id?: string }
        Returns: Json
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
      call_edge_function: {
        Args: { p_body?: Json; p_function_name: string }
        Returns: number
      }
      can_access_finance: { Args: never; Returns: boolean }
      can_send_re_engagement: {
        Args: { p_client_id: string; p_days?: number }
        Returns: boolean
      }
      cancel_booking: { Args: { p_booking_id: string }; Returns: Json }
      cancel_event_booking: { Args: { p_booking_id: string }; Returns: Json }
      client_has_active_push_tokens: {
        Args: { p_client_id: string }
        Returns: boolean
      }
      count_attended_lessons: { Args: { p_client_id: string }; Returns: number }
      create_user_profile: {
        Args: {
          full_name: string
          phone?: string
          role?: Database["public"]["Enums"]["user_role"]
          user_id: string
        }
        Returns: {
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
        SetofOptions: {
          from: "*"
          to: "profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      cron_process_notification_queue: { Args: never; Returns: undefined }
      cron_queue_birthday: { Args: never; Returns: undefined }
      cron_queue_entries_low: { Args: never; Returns: undefined }
      cron_queue_lesson_reminders: { Args: never; Returns: undefined }
      cron_queue_re_engagement: { Args: never; Returns: undefined }
      cron_queue_subscription_expiry: { Args: never; Returns: undefined }
      fix_missing_cancel_restore_entries: {
        Args: never
        Returns: {
          booking_id: string
          restored: boolean
          subscription_id: string
        }[]
      }
      generate_slug_from_discipline: {
        Args: { discipline_text: string }
        Returns: string
      }
      get_financial_kpis: {
        Args: { p_month_end?: string; p_month_start?: string }
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
      get_notification_channel: {
        Args: {
          p_category: Database["public"]["Enums"]["notification_category"]
          p_client_id: string
        }
        Returns: Database["public"]["Enums"]["notification_channel"]
      }
      get_revenue_breakdown: {
        Args: { p_month_end?: string; p_month_start?: string }
        Returns: Json
      }
      get_unread_notifications_count: { Args: never; Returns: number }
      is_admin: { Args: never; Returns: boolean }
      is_finance: { Args: never; Returns: boolean }
      is_staff: { Args: never; Returns: boolean }
      mark_all_notifications_read: { Args: never; Returns: number }
      mark_notification_read: {
        Args: { p_announcement_id?: string; p_notification_log_id?: string }
        Returns: boolean
      }
      milestone_already_sent: {
        Args: { p_client_id: string; p_milestone: number }
        Returns: boolean
      }
      queue_announcement:
        | {
            Args: { p_announcement_id: string; p_body: string; p_title: string }
            Returns: Json
          }
        | {
            Args: {
              p_announcement_id: string
              p_body: string
              p_scheduled_for?: string
              p_title: string
            }
            Returns: Json
          }
      queue_birthday: { Args: never; Returns: Json }
      queue_entries_low: { Args: never; Returns: Json }
      queue_first_lesson: { Args: { p_client_id: string }; Returns: boolean }
      queue_lesson_reminders: { Args: never; Returns: Json }
      queue_milestone: {
        Args: { p_client_id: string; p_milestone: number }
        Returns: boolean
      }
      queue_new_event: {
        Args: { p_event_date: string; p_event_id: string; p_event_name: string }
        Returns: Json
      }
      queue_re_engagement: { Args: never; Returns: Json }
      queue_subscription_expiry: { Args: never; Returns: Json }
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
      staff_cancel_booking: { Args: { p_booking_id: string }; Returns: Json }
      staff_cancel_event_booking: {
        Args: { p_booking_id: string }
        Returns: Json
      }
      staff_get_user_email_status: {
        Args: { p_user_id: string }
        Returns: Json
      }
      staff_update_booking_status: {
        Args: {
          p_booking_id: string
          p_status: Database["public"]["Enums"]["booking_status"]
        }
        Returns: Json
      }
    }
    Enums: {
      booking_status: "booked" | "canceled" | "attended" | "no_show"
      bug_status: "open" | "in_progress" | "resolved" | "closed"
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
      notification_channel: "push" | "email"
      notification_status:
        | "pending"
        | "sent"
        | "delivered"
        | "failed"
        | "skipped"
      subscription_status: "active" | "completed" | "expired" | "canceled"
      user_role: "user" | "operator" | "admin" | "finance"
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
  public: {
    Enums: {
      booking_status: ["booked", "canceled", "attended", "no_show"],
      bug_status: ["open", "in_progress", "resolved", "closed"],
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
      ],
      notification_channel: ["push", "email"],
      notification_status: [
        "pending",
        "sent",
        "delivered",
        "failed",
        "skipped",
      ],
      subscription_status: ["active", "completed", "expired", "canceled"],
      user_role: ["user", "operator", "admin", "finance"],
    },
  },
} as const
