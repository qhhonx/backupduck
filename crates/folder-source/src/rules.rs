use backupduck_core::{Error, Result};
use globset::{GlobBuilder, GlobSet, GlobSetBuilder};

pub(crate) struct Rules {
    include: GlobSet,
    exclude: GlobSet,
}
impl Rules {
    pub fn compile(include: &[String], exclude: &[String]) -> Result<Self> {
        fn compile(patterns: &[String]) -> Result<GlobSet> {
            if patterns.len() > 128 || patterns.iter().map(String::len).sum::<usize>() > 65536 {
                return Err(Error::Invalid("too many folder patterns".into()));
            }
            let mut builder = GlobSetBuilder::new();
            for pattern in patterns {
                if pattern.is_empty()
                    || pattern.len() > 2048
                    || pattern.starts_with('/')
                    || pattern.split('/').any(|part| part == "..")
                {
                    return Err(Error::Invalid(format!("invalid folder pattern: {pattern}")));
                }
                // A folder token such as Drafts/ includes its descendants.
                let expanded = if pattern.ends_with('/') {
                    format!("{pattern}**")
                } else {
                    pattern.clone()
                };
                let glob = GlobBuilder::new(&expanded)
                    .literal_separator(true)
                    .backslash_escape(true)
                    .build()
                    .map_err(|e| Error::Invalid(format!("{pattern}: {e}")))?;
                builder.add(glob);
            }
            builder.build().map_err(|e| Error::Invalid(e.to_string()))
        }
        Ok(Self {
            include: compile(include)?,
            exclude: compile(exclude)?,
        })
    }
    pub fn allows(&self, relative: &str) -> bool {
        (self.include.is_empty() || self.include.is_match(relative))
            && !self.exclude.is_match(relative)
    }
}
