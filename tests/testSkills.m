classdef testSkills < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addSourceToPath(tc)
            here = fileparts(mfilename("fullpath"));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(here), "src")));
        end
    end

    methods (Test)
        function rootFindsRepositorySkillsDirectory(tc)
            folder = fomc.skills.root();
            tc.verifyTrue(isfolder(folder));
            tc.verifyTrue(isfile(fullfile(folder, "fomc-score", "SKILL.md")));
            tc.verifyTrue(isfile(fullfile(folder, "fomc-score", "schema.json")));
        end

        function frontmatterHasNameAndDescription(tc)
            skillFile = fullfile(fomc.skills.root(), "fomc-score", "SKILL.md");
            metadata = fomc.skills.parseFrontmatter(string(skillFile));
            tc.verifyEqual(metadata.name, "fomc-score");
            tc.verifyNotEmpty(metadata.description);
        end

        function listReturnsSkillsWithFrontmatter(tc)
            skills = fomc.skills.list();
            i = find(string({skills.name}) == "fomc-score", 1);
            tc.verifyNotEmpty(i);
            tc.verifyNotEmpty(skills(i).description);
        end

        function systemPromptListsSkillsAndInstructionsToLoadThem(tc)
            prompt = fomc.systemPrompt();
            tc.verifySubstring(prompt, "## Skills");
            tc.verifySubstring(prompt, "Available skills:");
            tc.verifySubstring(prompt, "- fomc-score:");
            tc.verifySubstring(prompt, "call readSkill with the skill's name");
            tc.verifySubstring(prompt, "numeric comparisons across meetings");
            tc.verifySubstring(prompt, "Do not answer scoring requests from memory.");
        end

        function scoringIntentDetectionIsTargeted(tc)
            tc.verifyTrue(fomc.focus.wantsScoring("Score the minutes for 2020-01-29."));
            tc.verifyTrue(fomc.focus.wantsScoring("Compare FOMC stance numerically across meetings."));
            tc.verifyTrue(fomc.focus.wantsScoring("What was the overall tone of the FOMC minutes?"));
            tc.verifyFalse(fomc.focus.wantsScoring( ...
                "What was the tone of the inflation discussion in the minutes?"));
            tc.verifyFalse(fomc.focus.wantsScoring( ...
                "What stance did participants take on the labor market?"));
            tc.verifyFalse(fomc.focus.wantsScoring("What was the target rate after the meeting?"));
        end

        function skillExampleReferenceUsesExistingFilename(tc)
            skillFile = fomc.skills.read("fomc-score");
            exampleFile = fullfile(fomc.skills.root(), "fomc-score", ...
                "examples", "exampleOutput.json");
            tc.verifyTrue(isfile(exampleFile));
            tc.verifySubstring(skillFile, "examples/exampleOutput.json");
        end

        function readDefaultsToSkillMarkdownAndReadsNestedFiles(tc)
            skillFile = fomc.skills.read("fomc-score");
            schema = fomc.skills.read("fomc-score", "schema.json");
            rubric = fomc.skills.read("fomc-score", "rubric/ratePath.md");
            tc.verifySubstring(skillFile, "FOMC Minutes Scoring");
            tc.verifySubstring(schema, """meeting_date""");
            tc.verifyNotEmpty(rubric);
        end

        function readRejectsPathsOutsideSkill(tc)
            tc.verifyError(@() fomc.skills.read("fomc-score", "../README.md"), ...
                "fomc:skills:invalidFile");
        end
    end
end
