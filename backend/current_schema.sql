--
-- PostgreSQL database dump
--
-- NOTE: this dump is from 2025-08-01 (last touched alongside
-- migration_signup_fields.sql) and is STALE — every migration_*.sql file in
-- this directory with a later date has been applied to the live database but
-- never captured in a fresh pg_dump. Treat every migration file as more
-- authoritative than this dump for the tables/columns it touches. As of
-- batch 9, that's at least:
--   - `notifications` table — entirely missing here (migration_notifications.sql)
--   - `league_groups`, `group_members` tables — entirely missing here
--     (migration_group_formats.sql, migration_group_membership_history.sql,
--     migration_nested_groups.sql)
--   - `league_audit_log`, `league_announcements` tables — entirely missing
--     here (migration_audit_log.sql, migration_announcements.sql, batch 9)
--   - `users.is_guest` (migration_guest_players.sql), `users.deleted_at`
--     (migration_account_deletion.sql) — missing from the `users` table below
--   - `users.city` shown below no longer exists — dropped by
--     migration_drop_dead_columns.sql (batch 9)
--   - `league_members.is_co_host` (migration_co_hosts.sql), `.partner_id`/
--     `.partner_status` (migration_doubles_everywhere.sql) — missing below;
--     `league_members.group_id` shown below no longer exists — dropped by
--     migration_drop_dead_columns.sql (batch 9), superseded by `group_members`
--   - `leagues.partner_mode` (migration_doubles_everywhere.sql),
--     `.points_enabled`/`.points_win`/`.points_loss`
--     (migration_custom_points.sql), `.max_players`
--     (migration_league_capacity.sql), `.registration_start`/
--     `.registration_end`/`.status` (migration_registration_and_status.sql,
--     batch 9 — hand-applied to prod earlier with no migration file until now)
--     — none shown on the `leagues` table below
--   - `scheduled_matches.venue`/`playoff_matches.scheduled_time`/`.venue`
--     (migration_venue_and_playoff_time.sql), `.group_id` on both tables
--     (migration_group_formats.sql) — missing below
--   - `matches.photo_url`/`playoff_matches.photo_url`
--     (migration_match_photos.sql, batch 9) — missing below
--   - `user_sports.rating` shown below as numeric(6,1) — widened to
--     numeric(6,2) by migration_rating_precision.sql
--
-- Run `npm run dump-schema` (added in batch 9 — see package.json) against a
-- real database connection to regenerate this file from scratch instead of
-- trusting the hand-reconciled notes above.

\restrict Jsi5gZP2x6Y7okLwm5r2zFg2zp6JvqYLA35STEb6a7mSBkrRRxosLw2yAUq8IPb

-- Dumped from database version 18.4
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: league_members; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.league_members (
    id integer NOT NULL,
    league_id integer,
    user_id integer,
    joined_at timestamp without time zone DEFAULT now(),
    points integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.league_members OWNER TO postgres;

--
-- Name: league_members_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.league_members_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.league_members_id_seq OWNER TO postgres;

--
-- Name: league_members_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.league_members_id_seq OWNED BY public.league_members.id;


--
-- Name: leagues; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.leagues (
    id integer NOT NULL,
    sport character varying(50) NOT NULL,
    area character varying(50) NOT NULL,
    season_start date NOT NULL,
    season_end date NOT NULL,
    created_by integer,
    created_at timestamp without time zone DEFAULT now(),
    format character varying(10) DEFAULT 'singles'::character varying NOT NULL,
    gender_category character varying(10) DEFAULT 'mens'::character varying NOT NULL,
    schedule_type character varying(20) DEFAULT 'round_robin'::character varying NOT NULL,
    matches_per_player integer,
    host_enters_scores boolean DEFAULT false NOT NULL,
    name character varying(100) DEFAULT 'Unnamed League'::character varying NOT NULL,
    is_private boolean DEFAULT false NOT NULL,
    join_code character varying(8),
    academy_name character varying(100),
    min_rating numeric,
    max_rating numeric
);


ALTER TABLE public.leagues OWNER TO postgres;

--
-- Name: leagues_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.leagues_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.leagues_id_seq OWNER TO postgres;

--
-- Name: leagues_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.leagues_id_seq OWNED BY public.leagues.id;


--
-- Name: matches; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.matches (
    id integer NOT NULL,
    league_id integer,
    player1_id integer,
    player2_id integer,
    player1_units integer,
    player2_units integer,
    winner_id integer,
    reported_by integer,
    status character varying(20) DEFAULT 'pending'::character varying,
    created_at timestamp without time zone DEFAULT now(),
    format character varying(10) DEFAULT 'singles'::character varying NOT NULL,
    player1_partner_id integer,
    player2_partner_id integer,
    set_scores text,
    scheduled_match_id integer,
    player1_rating_change numeric(5,2),
    player2_rating_change numeric(5,2),
    player1_partner_rating_change numeric(5,2),
    player2_partner_rating_change numeric(5,2),
    league_points_awarded integer
);


ALTER TABLE public.matches OWNER TO postgres;

--
-- Name: matches_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.matches_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.matches_id_seq OWNER TO postgres;

--
-- Name: matches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.matches_id_seq OWNED BY public.matches.id;


--
-- Name: playoff_matches; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.playoff_matches (
    id integer NOT NULL,
    league_id integer,
    round_number integer NOT NULL,
    "position" integer NOT NULL,
    player1_id integer,
    player2_id integer,
    winner_id integer,
    player1_units integer,
    player2_units integer,
    set_scores text,
    status character varying(20) DEFAULT 'pending'::character varying,
    reported_by integer,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.playoff_matches OWNER TO postgres;

--
-- Name: playoff_matches_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.playoff_matches_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.playoff_matches_id_seq OWNER TO postgres;

--
-- Name: playoff_matches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.playoff_matches_id_seq OWNED BY public.playoff_matches.id;


--
-- Name: scheduled_matches; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scheduled_matches (
    id integer NOT NULL,
    league_id integer,
    tier_number integer NOT NULL,
    player1_id integer,
    player1_partner_id integer,
    player2_id integer,
    player2_partner_id integer,
    created_at timestamp without time zone DEFAULT now(),
    scheduled_time timestamp without time zone
);


ALTER TABLE public.scheduled_matches OWNER TO postgres;

--
-- Name: scheduled_matches_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.scheduled_matches_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.scheduled_matches_id_seq OWNER TO postgres;

--
-- Name: scheduled_matches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.scheduled_matches_id_seq OWNED BY public.scheduled_matches.id;


--
-- Name: user_sports; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_sports (
    id integer NOT NULL,
    user_id integer,
    sport character varying(50) NOT NULL,
    rating numeric(6,1) DEFAULT 1000,
    matches_played integer DEFAULT 0,
    wins integer DEFAULT 0,
    losses integer DEFAULT 0,
    format character varying(10) DEFAULT 'singles'::character varying NOT NULL
);


ALTER TABLE public.user_sports OWNER TO postgres;

--
-- Name: user_sports_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_sports_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_sports_id_seq OWNER TO postgres;

--
-- Name: user_sports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_sports_id_seq OWNED BY public.user_sports.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id integer NOT NULL,
    username character varying(30) NOT NULL,
    phone_number character varying(15) NOT NULL,
    password_hash text NOT NULL,
    profile_pic_url text,
    created_at timestamp without time zone DEFAULT now(),
    location character varying(50),
    gender character varying(1),
    first_name character varying(50),
    last_name character varying(50),
    email character varying(255),
    city character varying(50) DEFAULT 'Bangalore'::character varying
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: league_members id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.league_members ALTER COLUMN id SET DEFAULT nextval('public.league_members_id_seq'::regclass);


--
-- Name: leagues id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leagues ALTER COLUMN id SET DEFAULT nextval('public.leagues_id_seq'::regclass);


--
-- Name: matches id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches ALTER COLUMN id SET DEFAULT nextval('public.matches_id_seq'::regclass);


--
-- Name: playoff_matches id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.playoff_matches ALTER COLUMN id SET DEFAULT nextval('public.playoff_matches_id_seq'::regclass);


--
-- Name: scheduled_matches id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scheduled_matches ALTER COLUMN id SET DEFAULT nextval('public.scheduled_matches_id_seq'::regclass);


--
-- Name: user_sports id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sports ALTER COLUMN id SET DEFAULT nextval('public.user_sports_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: league_members league_members_league_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.league_members
    ADD CONSTRAINT league_members_league_id_user_id_key UNIQUE (league_id, user_id);


--
-- Name: league_members league_members_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.league_members
    ADD CONSTRAINT league_members_pkey PRIMARY KEY (id);


--
-- Name: leagues leagues_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leagues
    ADD CONSTRAINT leagues_pkey PRIMARY KEY (id);


--
-- Name: matches matches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_pkey PRIMARY KEY (id);


--
-- Name: playoff_matches playoff_matches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.playoff_matches
    ADD CONSTRAINT playoff_matches_pkey PRIMARY KEY (id);


--
-- Name: scheduled_matches scheduled_matches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scheduled_matches
    ADD CONSTRAINT scheduled_matches_pkey PRIMARY KEY (id);


--
-- Name: user_sports user_sports_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sports
    ADD CONSTRAINT user_sports_pkey PRIMARY KEY (id);


--
-- Name: user_sports user_sports_user_sport_format_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sports
    ADD CONSTRAINT user_sports_user_sport_format_key UNIQUE (user_id, sport, format);


--
-- Name: users users_phone_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_number_key UNIQUE (phone_number);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


-- users_username_key (UNIQUE on username) was dropped by
-- migration_signup_fields.sql: username is now an auto-derived "First Last"
-- display name, not a unique handle, and users_email_lower_key (below)
-- became the real uniqueness constraint on identity.

--
-- Name: users_email_lower_key; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX users_email_lower_key ON public.users USING btree (lower((email)::text)) WHERE (email IS NOT NULL);


--
-- Name: idx_league_members_league; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_league_members_league ON public.league_members USING btree (league_id);


--
-- Name: idx_leagues_sport_area; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_leagues_sport_area ON public.leagues USING btree (sport, area);


--
-- Name: idx_playoff_matches_league; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_playoff_matches_league ON public.playoff_matches USING btree (league_id);


--
-- Name: idx_users_phone_number; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_phone_number ON public.users USING btree (phone_number);


--
-- Name: idx_users_username; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_users_username ON public.users USING btree (username);


--
-- Name: league_members league_members_league_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.league_members
    ADD CONSTRAINT league_members_league_id_fkey FOREIGN KEY (league_id) REFERENCES public.leagues(id) ON DELETE CASCADE;


--
-- Name: league_members league_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.league_members
    ADD CONSTRAINT league_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: leagues leagues_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leagues
    ADD CONSTRAINT leagues_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: matches matches_league_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_league_id_fkey FOREIGN KEY (league_id) REFERENCES public.leagues(id) ON DELETE CASCADE;


--
-- Name: matches matches_player1_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_player1_id_fkey FOREIGN KEY (player1_id) REFERENCES public.users(id);


--
-- Name: matches matches_player1_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_player1_partner_id_fkey FOREIGN KEY (player1_partner_id) REFERENCES public.users(id);


--
-- Name: matches matches_player2_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_player2_id_fkey FOREIGN KEY (player2_id) REFERENCES public.users(id);


--
-- Name: matches matches_player2_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_player2_partner_id_fkey FOREIGN KEY (player2_partner_id) REFERENCES public.users(id);


--
-- Name: matches matches_reported_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES public.users(id);


--
-- Name: matches matches_scheduled_match_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_scheduled_match_id_fkey FOREIGN KEY (scheduled_match_id) REFERENCES public.scheduled_matches(id);


--
-- Name: matches matches_winner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_winner_id_fkey FOREIGN KEY (winner_id) REFERENCES public.users(id);


--
-- Name: playoff_matches playoff_matches_league_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.playoff_matches
    ADD CONSTRAINT playoff_matches_league_id_fkey FOREIGN KEY (league_id) REFERENCES public.leagues(id) ON DELETE CASCADE;


--
-- Name: playoff_matches playoff_matches_player1_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.playoff_matches
    ADD CONSTRAINT playoff_matches_player1_id_fkey FOREIGN KEY (player1_id) REFERENCES public.users(id);


--
-- Name: playoff_matches playoff_matches_player2_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.playoff_matches
    ADD CONSTRAINT playoff_matches_player2_id_fkey FOREIGN KEY (player2_id) REFERENCES public.users(id);


--
-- Name: playoff_matches playoff_matches_reported_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.playoff_matches
    ADD CONSTRAINT playoff_matches_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES public.users(id);


--
-- Name: playoff_matches playoff_matches_winner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.playoff_matches
    ADD CONSTRAINT playoff_matches_winner_id_fkey FOREIGN KEY (winner_id) REFERENCES public.users(id);


--
-- Name: scheduled_matches scheduled_matches_league_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scheduled_matches
    ADD CONSTRAINT scheduled_matches_league_id_fkey FOREIGN KEY (league_id) REFERENCES public.leagues(id) ON DELETE CASCADE;


--
-- Name: scheduled_matches scheduled_matches_player1_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scheduled_matches
    ADD CONSTRAINT scheduled_matches_player1_id_fkey FOREIGN KEY (player1_id) REFERENCES public.users(id);


--
-- Name: scheduled_matches scheduled_matches_player1_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scheduled_matches
    ADD CONSTRAINT scheduled_matches_player1_partner_id_fkey FOREIGN KEY (player1_partner_id) REFERENCES public.users(id);


--
-- Name: scheduled_matches scheduled_matches_player2_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scheduled_matches
    ADD CONSTRAINT scheduled_matches_player2_id_fkey FOREIGN KEY (player2_id) REFERENCES public.users(id);


--
-- Name: scheduled_matches scheduled_matches_player2_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scheduled_matches
    ADD CONSTRAINT scheduled_matches_player2_partner_id_fkey FOREIGN KEY (player2_partner_id) REFERENCES public.users(id);


--
-- Name: user_sports user_sports_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sports
    ADD CONSTRAINT user_sports_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict Jsi5gZP2x6Y7okLwm5r2zFg2zp6JvqYLA35STEb6a7mSBkrRRxosLw2yAUq8IPb

