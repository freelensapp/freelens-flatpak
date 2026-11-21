#!/usr/bin/env perl

# Usage and rules: "Release Notes" in AGENTS.md.

use strict;
use warnings;
use utf8;

binmode STDIN,  ':encoding(UTF-8)';
binmode STDOUT, ':encoding(UTF-8)';

my $indent = shift // '';

sub escape {
    my ($text) = @_;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    return $text;
}

sub inline {
    my ($text) = @_;

    # References to pull requests and issues, which mean nothing outside GitHub.
    $text =~ s/\s*See (?:#\d+|\[[^\]]*\]\([^)]*\))(?:,\s*#\d+)*\.?//g;

    my $out = '';
    for my $part (split /(`[^`]*`)/, $text) {
        if ($part =~ /\A`(.*)`\z/s) {
            $out .= '<code>' . escape($1) . '</code>';
            next;
        }
        $part =~ s/\[([^\]]*)\]\([^)]*\)/$1/g;
        $part =~ s/\*\*([^*]+)\*\*/$1/g;
        $part = escape($part);
        $part =~ s/(?<![\w*])[*_]([^*_]+)[*_](?![\w*])/<em>$1<\/em>/g;
        $out .= $part;
    }
    $out =~ s/\s+\z//;
    return $out;
}

my $body = do { local $/; <STDIN> };
$body =~ s/\r//g;

# The summary is everything above the first section of changes.
$body =~ s/^###\s.*\z//ms;

my @out;
for my $block (split /\n\s*\n/, $body) {
    my @lines = grep { /\S/ && !/^\s*#/ } split /\n/, $block;
    next unless @lines;
    if ($lines[0] =~ /^\s*[*-]\s/) {
        push @out, "$indent<ul>";
        for (@lines) {
            if (/^\s*[*-]\s+(.*)/) {
                push @out, "$indent  <li>" . inline($1) . '</li>';
            }
            else {
                (my $line = $_) =~ s/^\s+//;
                $out[-1] =~ s{</li>\z}{' ' . inline($line) . '</li>'}e;
            }
        }
        push @out, "$indent</ul>";
    }
    else {
        s/^\s+|\s+$//g for @lines;
        my $paragraph = inline(join ' ', @lines);
        push @out, "$indent<p>$paragraph</p>" if length $paragraph;
    }
}

print "$_\n" for @out;
