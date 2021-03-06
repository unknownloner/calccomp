module Asm.Parser (printTree
                  , parseText
                  , parseFile
                  , parseStatement
                  , parseArg) where

import Asm.Expr
import Asm.Preprocess
import Text.Parsec hiding (space, spaces, hexDigit)
import Text.Parsec.Expr
import Text.Parsec.String (Parser)
import Numeric
import Control.Monad
import Data.Maybe (catMaybes)
import Data.Char (ord, toUpper)


-- Lexer
parseBin :: String -> Integer
parseBin = foldl (\l r -> l * 2 + (if r == '1' then 1 else 0)) 0

hexDigit :: Parser Char
hexDigit = oneOf "abcdefABCDEF0123456789"

binPrefix :: Parser Integer
binPrefix = do
    char '%'
    str <- many1 $ oneOf "01"
    return $ parseBin str

binSuffix :: Parser Integer
binSuffix = do
    str <- many1 $ oneOf "01"
    oneOf "Bb"
    return $ parseBin str

binary :: Parser Integer
binary = binPrefix <|> binSuffix

hexPrefix :: Parser Integer
hexPrefix = do
    char '$'
    str <- many1 hexDigit
    return $ fst . head . readHex $ str

hexSuffix :: Parser Integer
hexSuffix = do
    str <- many1 hexDigit
    oneOf "Hh"
    return $ fst . head . readHex $ str

hexadecimal :: Parser Integer
hexadecimal = hexPrefix <|> hexSuffix

decimal :: Parser Integer
decimal = do
    str <- many1 digit
    return $ read str

charNum :: Parser Integer
charNum = do
    char '\''
    c <- anyChar
    char '\''
    return $ toInteger (ord c)

integer :: Parser Integer
integer = lexeme $ do
    sign <- option '+' (oneOf "+-")
    num <- try hexadecimal <|> try binary <|> try decimal <|> try charNum
    notFollowedBy lblChar
    return $ if sign == '+' then num else -num

space :: Parser Char
space = char ' '

spaces :: Parser String
spaces = many1 space

tabs :: Parser String
tabs = many1 tab

comment :: Parser String
comment = do
    char ';'
    many (try $ noneOf "\n")

whiteSpace :: Parser ()
whiteSpace = skipMany (spaces <|> tabs <|> comment)

lexeme :: Parser a -> Parser a
lexeme p = do
    x <- p
    whiteSpace
    return x

stringNoCase :: String -> Parser String
stringNoCase "" = return ""
stringNoCase (s:str) = do
    l <- satisfy (\c -> toUpper c == toUpper s)
    r <- stringNoCase str
    return $ l:r

symbol :: String -> Parser String
symbol = lexeme . stringNoCase

parens :: Parser a -> Parser a
parens p = do
    symbol "("
    x <- p
    symbol ")"
    return x

braces :: Parser a -> Parser a
braces p = do
    symbol "{"
    x <- p
    symbol "}"
    return x

semi :: Parser String
semi = symbol ";"

comma :: Parser String
comma = symbol ","

operator :: Parser String
operator = lexeme $ do
    op <- oneOf "+-*/><%"
    end <- case op of
        '>' -> option "" (try (string ">"))
        '<' -> option "" (try (string "<"))
        _ -> return ""
    return $ op:end

identifier :: Parser String
identifier = lexeme $ do
    x <- letter <|> char '_'
    xs <- many (alphaNum <|> char '_')
    return $ x:xs

commaSep :: Parser a -> Parser [a]
commaSep p = lexeme $ p `sepBy` comma

semiSep :: Parser a -> Parser [a]
semiSep p = lexeme $ p `sepBy` semi

stringEscape :: Parser Char
stringEscape = char '\'' >> oneOf "\\\""

stringLiteral :: Parser String
stringLiteral = lexeme $ do
    char '"'
    str <- many (stringEscape <|> noneOf "\"")
    char '"'
    return str

singleton :: Parser a -> Parser [a]
singleton = liftM (:[])

lblChar :: Parser Char
lblChar = alphaNum <|> char '_'

lblIdentifier :: Parser String
lblIdentifier = lexeme $ many1 lblChar

parseMaybe :: (String -> Maybe b) -> Parser b
parseMaybe f = do
    ident <- identifier
    case f ident of
        Nothing -> parserZero
        Just x -> return x

-- Parser
asmlabel :: Parser Expr
asmlabel = lexeme $ do
    name <- lblIdentifier
    char ':'
    return $ LabelDef name

condition :: Parser Expr
condition = Cond `fmap` parseMaybe readCondMaybe

instr :: Parser Expr
instr = do
    instr <- parseMaybe readMaybeUpper
    args <- case instr of
            CALL -> jpCond
            JR -> jpCond
            JP -> jpCond
            RET -> option [] (try $ singleton condition)
            _ -> commaSep argExpr
    return $ Instr instr args
    where jpCond = do
              cond <- option [] (try $ do
                  x <- condition
                  symbol ","
                  return [x])
              arg <- argExpr
              return $ cond ++ [arg]

num :: Parser Expr
num = do
    x <- integer
    return $ Literal (Num $ fromIntegral x)

labelref :: Parser Expr
labelref = do
    ident <- lblIdentifier <|> symbol "$"
    return $ Literal (Label ident)

constAssign :: Parser Expr
constAssign = do
    name <- lblIdentifier
    symbol "=" <|> (optional (char '.') >> symbol "equ")
    val <- argExpr
    return $ Define name val

asmstring :: Parser Expr
asmstring = String `fmap` stringLiteral

register :: Parser Expr
register = do
    reg <- parseMaybe readMaybeUpper
    return $ if regIs8Bit reg then Reg8 reg
        else case reg of
            IX -> Reg16Index IX
            IY -> Reg16Index IY
            _ -> Reg16 reg

regIndirect :: Parser Expr
regIndirect = do
    regName <- parens $ choice [
                symbol "hl",
                symbol "de",
                symbol "bc",
                try $ symbol "ix",
                symbol "iy",
                symbol "sp",
                symbol "c"
            ]
    return $ case regName of
        "ix" -> RegIndex IX (Literal $ Num 0)
        "iy" -> RegIndex IY (Literal $ Num 0)
        "hl" -> Reg8 HL'
        _ -> RegIndir $ readReg regName

regIndex :: Parser Expr
regIndex = parens $ do
    reg <- try $ symbol "ix" <|> symbol "iy"
    op <- symbol "+" <|> symbol "-"
    arg <- mathExpr
    return $ RegIndex (readReg reg) $ case op of
        "+" -> arg
        "-" -> Binop Mul (litNum (-1)) arg

addrIndirect :: Parser Expr
addrIndirect = do
    addr <- parens mathExpr
    return $ AddrIndir addr

directive :: Parser Expr
directive = do
    oneOf "#."
    ident <- identifier
    args <- commaSep directiveArg
    return $ Directive ident args

mathOp :: Parser (Expr -> Expr -> Expr)
mathOp = do
    op <- operator
    return $ case op of
                "+" -> Binop Add
                "-" -> Binop Sub
                "*" -> Binop Mul
                "/" -> Binop Div
                "<" -> Binop Lt
                ">" -> Binop Gt
                "%" -> Binop Mod
                "<<" -> Binop LShift
                ">>" -> Binop RShift
                "|" -> Binop Or
                "&" -> Binop And
                "^" -> Binop Xor

parensExpr :: Parser Expr -> Parser Expr
parensExpr p = do
    xpr <- parens p
    return $ Parens xpr

antiQuoteExpr :: Parser Expr
antiQuoteExpr = do
    symbol "@{"
    q <- many $ noneOf "}"
    symbol "}"
    return $ AntiQuote q

antiQuoteStr :: Parser Expr
antiQuoteStr = do
    symbol "@s{"
    q <- many $ noneOf "}"
    symbol "}"
    return $ AntiQuoteStr q

antiQuote = try antiQuoteStr <|> antiQuoteExpr

binOp :: Parser Expr
binOp = chainl1 (try num <|> try antiQuote <|> try labelref <|> try (parensExpr mathExpr)) mathOp

mathExpr :: Parser Expr
mathExpr = try binOp
        <|> try num
        <|> try antiQuote
        <|> labelref

directiveArg :: Parser Expr
directiveArg = try mathExpr
            <|> asmstring
            <|> parens directiveArg

argExpr :: Parser Expr
argExpr = try register
       <|> try regIndirect
       <|> try regIndex
       <|> try binOp
       <|> antiQuote


statement :: Parser Expr
statement = try antiQuoteExpr <|> try directive <|> try constAssign <|> try asmlabel <|> instr

parseStatements :: Parser [Expr]
parseStatements = do
    let parseLine = whiteSpace >> optionMaybe (try statement)
    stmnts <- parseLine `sepBy` many1 newline
    return $ catMaybes stmnts

-- Convert top level 'Parens' exprs to AddrIndir exprs. Consider merging with 'removeParens' pass
indirPass :: [Expr] -> [Expr]
indirPass = map conv
    where conv (Instr i args) = Instr i (map convParens args)
          conv x = x
          convParens (Parens xpr) = AddrIndir xpr
          convParens x = x

-- Remove 'Parens' exprs, as we no longer need them
removeParens :: [Expr] -> [Expr]
removeParens = map conv
    where conv (Parens xpr) = conv xpr
          conv (Binop op l r) = Binop op (conv l) (conv r)
          conv (Directive str xs) = Directive str (removeParens xs)
          conv (Define str xpr) = Define str (conv xpr)
          conv (RegIndex r xpr) = RegIndex r (conv xpr)
          conv (Instr i xs) = Instr i (removeParens xs)
          conv xpr = xpr

-- Parses an argument
parseArg :: String -> Either String Expr
parseArg x = case parse (whiteSpace >> argExpr) "" x of
               Left err -> Left $ show err
               Right ast -> Right . head . removeParens . indirPass $ [ast]

-- Parses a single statement
parseStatement :: String -> Either String Expr
parseStatement x = case parse (whiteSpace >> statement) "" x of
    Left err -> Left $ show err
    Right ast -> Right . head . removeParens . indirPass $ [ast]

-- preprocesses and parses text; returns an error or an AST
-- parseText contents fname will parse contents and report errors as coming from fname
parseText :: String -> String -> Either String [Expr]
parseText fname contents =
    case parse parseStatements fname (preprocess contents) of
        Left err -> Left $ show err
        Right ast -> Right $ removeParens . indirPass $ ast

-- reads, preprocesses, and parses a file. Reads with #includes
parseFile :: FilePath -> IO (Either String [Expr])
parseFile fname = do
    contents <- readWithIncludes fname
    return $ parseText fname contents

printTree :: [Expr] -> String
printTree xprs = unlines (map show xprs)
